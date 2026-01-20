import SwiftUI
import SwiftData

struct DebtPayoffPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DebtAccount.createdDate, order: .reverse) private var debts: [DebtAccount]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    @State private var showingAddDebt = false
    @State private var showingQuickPayment = false
    @State private var selectedDebtForPayment: DebtAccount?
    @State private var paymentAmount = ""

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
                        VStack(spacing: AppTheme.Spacing.tight) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                                    Text("Total Debt")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalDebt, format: .currency(code: currencyCode))
                                        .appTitleText()
                                        .fontWeight(.bold)
                                        .foregroundStyle(AppColors.danger(for: appColorMode))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppTheme.Spacing.micro) {
                                    Text("Monthly Payment")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalMonthlyPayment, format: .currency(code: currencyCode))
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
                                        .foregroundStyle(AppColors.success(for: appColorMode))
                                }
                            }

                            ProgressView(value: overallPayoffProgress)
                                .tint(AppColors.tint(for: appColorMode))
                        }
                        .padding(.vertical, AppTheme.Spacing.compact)
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
                                        .tint(AppColors.success(for: appColorMode))
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteDebt(debt)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .coordinateSpace(name: "DebtPayoffPlannerView.scroll")
            }
        }
        .toolbar {
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
    }

    // MARK: - Computed Properties

    private var totalDebt: Decimal {
        debts.reduce(0) { $0 + $1.currentBalance }
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
}

// MARK: - Debt Row

struct DebtRow: View {
    let debt: DebtAccount
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    private var color: Color {
        Color(hex: debt.colorHex) ?? AppColors.danger(for: appColorMode)
    }

    var body: some View {
        NavigationLink(destination: DebtDetailView(debt: debt)) {
            HStack(spacing: AppTheme.Spacing.medium) {
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
                            .foregroundStyle(AppColors.success(for: appColorMode))
                    } else {
                        Text("\(Int(debt.payoffProgressPercentage))%")
                            .appCaptionText()
                            .fontWeight(.bold)
                            .foregroundStyle(color)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text(debt.name)
                        .appSectionTitleText()

                    HStack(spacing: AppTheme.Spacing.xSmall) {
                        Text(debt.currentBalance, format: .currency(code: currencyCode))
                            .appSecondaryBodyText()
                            .foregroundStyle(.secondary)

                        if !debt.isPaidOff {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(debt.interestRatePercentage, format: .number.precision(.fractionLength(1)))% APR")
                                .appCaptionText()
                                .foregroundStyle(debt.isHighInterest ? AppColors.danger(for: appColorMode) : .secondary)
                        }
                    }

                    if let insight = debt.smartInsight {
                        Text(insight)
                            .appCaptionText()
                            .foregroundStyle(debt.isPaidOff ? AppColors.success(for: appColorMode) : color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.compact)
        }
    }
}

#Preview {
    NavigationStack {
        DebtPayoffPlannerView()
    }
    .modelContainer(for: [DebtAccount.self], inMemory: true)
}
