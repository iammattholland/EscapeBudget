import SwiftUI
import SwiftData

struct DebtPayoffPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DebtAccount.sortOrder) private var debts: [DebtAccount]
            @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    @State private var showingAddDebt = false
    @State private var showingQuickPayment = false
    @State private var selectedDebtForPayment: DebtAccount?
    @State private var paymentAmount = ""
    @State private var hasCheckedDemoData = false
    @State private var debtToDelete: DebtAccount?
    @State private var showingDeleteConfirmation = false
    @State private var isEditing = false

    var body: some View {
        Group {
            if debts.isEmpty {
                List {
                    ScrollOffsetReader(coordinateSpace: "DebtPayoffPlannerView.scroll", id: "DebtPayoffPlannerView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    EmptyDataCard(
                        systemImage: "creditcard.trianglebadge.exclamationmark",
                        title: "No Debts Tracked",
                        message: "Add your debts to see payoff projections and compare repayment strategies.",
                        actionTitle: "Add Debt",
                        action: { showingAddDebt = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .coordinateSpace(name: "DebtPayoffPlannerView.scroll")
            } else {
                List {
                    ScrollOffsetReader(coordinateSpace: "DebtPayoffPlannerView.scroll", id: "DebtPayoffPlannerView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    // Summary Card
                    Section {
                        VStack(spacing: AppDesign.Theme.Spacing.tight) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Total Debt")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalDebt, format: .currency(code: settings.currencyCode))
                                        .appTitleText()
                                        .fontWeight(.bold)
                                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Monthly Payment")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalMonthlyPayment, format: .currency(code: settings.currencyCode))
                                        .appTitleText()
                                }
                            }

                            if let debtFreeDate = projectedDebtFreeDate {
                                HStack {
                                    Text("Debt-free by")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(debtFreeDate, format: .dateTime.month().year())
                                        .appSecondaryBodyText()
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                                }
                            }

                            ProgressView(value: overallPayoffProgress)
                                .tint(AppDesign.Colors.tint(for: appColorMode))
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.compact)
                    }

                    // Debts List
                    Section {
                        ForEach(debts) { debt in
                            DebtRow(debt: debt)
                                .swipeActions(edge: .leading) {
                                    if !debt.isPaidOff {
                                        Button {
                                            selectedDebtForPayment = debt
                                            showingQuickPayment = true
                                        } label: {
                                            Label("Payment", systemImage: "minus.circle.fill")
                                        }
                                        .tint(AppDesign.Colors.success(for: appColorMode))
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        debtToDelete = debt
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove(perform: moveDebts)
                    }
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .coordinateSpace(name: "DebtPayoffPlannerView.scroll")
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !debts.isEmpty {
                    Button(isEditing ? "Done" : "Reorder") {
                        withAnimation {
                            isEditing.toggle()
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddDebt = true }) {
                    Label("Add Debt", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddDebt) {
            DebtFormView()
        }
        .alert("Record Payment for \(selectedDebtForPayment?.name ?? "Debt")", isPresented: $showingQuickPayment) {
            TextField("Amount", text: $paymentAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
                paymentAmount = ""
            }
            Button("Record") {
                recordPayment()
            }
        } message: {
            Text("How much did you pay?")
        }
        .alert("Delete Debt?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                debtToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let debt = debtToDelete {
                    deleteDebt(debt)
                }
                debtToDelete = nil
            }
        } message: {
            if let debt = debtToDelete {
                Text("Are you sure you want to delete \"\(debt.name)\"? This action cannot be undone.")
            }
        }
        .onAppear {
            seedDemoDataIfNeeded()
        }
    }

    // MARK: - Computed Properties

    private var totalDebt: Decimal {
        debts.reduce(0) { $0 + $1.effectiveBalance }
    }

    private var totalMonthlyPayment: Decimal {
        debts.reduce(0) { $0 + $1.totalMonthlyPayment }
    }

    private var overallPayoffProgress: Double {
        let totalOriginal = debts.reduce(Decimal(0)) { $0 + $1.originalBalance }
        guard totalOriginal > 0 else { return 0 }
        let totalPaid = totalOriginal - totalDebt
        return Double(truncating: (totalPaid / totalOriginal) as NSNumber)
    }

    private var projectedDebtFreeDate: Date? {
        // Find the latest payoff date among all debts
        debts.compactMap { $0.projectedPayoffDate }.max()
    }

    // MARK: - Actions

    private func deleteDebt(_ debt: DebtAccount) {
        modelContext.delete(debt)
        try? modelContext.save()
    }

    private func moveDebts(from source: IndexSet, to destination: Int) {
        var reorderedDebts = debts
        reorderedDebts.move(fromOffsets: source, toOffset: destination)

        for (index, debt) in reorderedDebts.enumerated() {
            debt.sortOrder = index
        }

        try? modelContext.save()
    }

    private func recordPayment() {
        guard let debt = selectedDebtForPayment,
              let amount = Decimal(string: paymentAmount),
              amount > 0 else {
            paymentAmount = ""
            return
        }

        debt.currentBalance = max(0, debt.currentBalance - amount)
        paymentAmount = ""
        selectedDebtForPayment = nil

        try? modelContext.save()
    }

    private func seedDemoDataIfNeeded() {
        guard settings.isDemoMode, !hasCheckedDemoData else { return }
        hasCheckedDemoData = true
        DemoDataService.ensureDemoDebtAccounts(modelContext: modelContext)
        try? modelContext.save()
    }
}

// MARK: - Debt Row

struct DebtRow: View {
    let debt: DebtAccount
        @Environment(\.appColorMode) private var appColorMode
        @Environment(\.appSettings) private var settings

    private var color: Color {
        Color(hex: debt.colorHex) ?? AppDesign.Colors.danger(for: appColorMode)
    }

    var body: some View {
        NavigationLink(destination: DebtDetailView(debt: debt)) {
            HStack(spacing: AppDesign.Theme.Spacing.medium) {
                // Circular Progress Ring
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: debt.payoffProgress)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    if debt.isPaidOff {
                        Image(systemName: "checkmark")
                            .appTitleText()
                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                    } else {
                        Text("\(Int(debt.payoffProgressPercentage))%")
                            .appCaptionText()
                            .fontWeight(.bold)
                            .foregroundStyle(color)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                    HStack {
                        Text(debt.name)
                            .appSectionTitleText()
                        if debt.linkedAccount != nil {
                            Image(systemName: "link")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                        Text(debt.effectiveBalance, format: .currency(code: settings.currencyCode))
                            .appSecondaryBodyText()
                            .foregroundStyle(.secondary)

                        if debt.isSyncedWithAccount {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .appCaption2Text()
                                .foregroundStyle(.secondary)
                        }

                        if !debt.isPaidOff {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(debt.interestRatePercentage, format: .number.precision(.fractionLength(1)))% APR")
                                .appCaptionText()
                                .foregroundStyle(debt.isHighInterest ? AppDesign.Colors.danger(for: appColorMode) : .secondary)
                        }
                    }

                    if let insight = debt.smartInsight {
                        Text(insight)
                            .appCaptionText()
                            .foregroundStyle(debt.isPaidOff ? AppDesign.Colors.success(for: appColorMode) : color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppDesign.Theme.Spacing.compact)
        }
    }
}

#Preview {
    NavigationStack {
        DebtPayoffPlannerView()
    }
    .modelContainer(for: [DebtAccount.self, Account.self], inMemory: true)
}
