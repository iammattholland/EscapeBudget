import SwiftUI
import SwiftData

struct BillsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringPurchase.nextDate) private var bills: [RecurringPurchase]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("isDemoMode") private var isDemoMode = false
    @Environment(\.appColorMode) private var appColorMode

    @State private var showingAddBill = false
    @State private var billToDelete: RecurringPurchase?
    @State private var showingDeleteConfirmation = false
    @State private var selectedFilter: BillFilter = .all
    @State private var hasCheckedDemoData = false

    enum BillFilter: String, CaseIterable {
        case all = "All"
        case upcoming = "Upcoming"
        case overdue = "Overdue"
        case inactive = "Inactive"
    }

    var body: some View {
        Group {
            if bills.isEmpty {
                List {
                    ScrollOffsetReader(coordinateSpace: "BillsDashboardView.scroll", id: "BillsDashboardView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    EmptyDataCard(
                        systemImage: "calendar.badge.clock",
                        title: "No Bills Tracked",
                        message: "Add your recurring bills to track due dates, totals, and never miss a payment.",
                        actionTitle: "Add Bill",
                        action: { showingAddBill = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .coordinateSpace(name: "BillsDashboardView.scroll")
            } else {
                List {
                    ScrollOffsetReader(coordinateSpace: "BillsDashboardView.scroll", id: "BillsDashboardView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    // Summary Card
                    Section {
                        VStack(spacing: AppDesign.Theme.Spacing.tight) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Monthly Total")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(monthlyTotal, format: .currency(code: currencyCode))
                                        .appTitleText()
                                        .fontWeight(.bold)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Active Bills")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text("\(activeBillsCount)")
                                        .appTitleText()
                                }
                            }

                            // Upcoming this week indicator
                            if upcomingThisWeekCount > 0 {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
                                    Text("\(upcomingThisWeekCount) bill\(upcomingThisWeekCount == 1 ? "" : "s") due this week")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(upcomingThisWeekTotal, format: .currency(code: currencyCode))
                                        .appSecondaryBodyText()
                                        .fontWeight(.medium)
                                }
                                .padding(.top, AppDesign.Theme.Spacing.xSmall)
                            }

                            if overdueCount > 0 {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                    Text("\(overdueCount) overdue bill\(overdueCount == 1 ? "" : "s")")
                                        .appCaptionText()
                                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                    Spacer()
                                }
                                .padding(.top, AppDesign.Theme.Spacing.xSmall)
                            }
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.compact)
                    }

                    // Filter Picker
                    Section {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(BillFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Bills List
                    Section {
                        ForEach(filteredBills) { bill in
                            BillRow(bill: bill)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        markAsPaid(bill)
                                    } label: {
                                        Label("Mark Paid", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(AppDesign.Colors.success(for: appColorMode))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        billToDelete = bill
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        toggleActive(bill)
                                    } label: {
                                        Label(bill.isActive ? "Pause" : "Resume", systemImage: bill.isActive ? "pause.circle" : "play.circle")
                                    }
                                    .tint(.orange)
                                }
                        }
                    } header: {
                        if !filteredBills.isEmpty {
                            Text("\(filteredBills.count) bill\(filteredBills.count == 1 ? "" : "s")")
                        }
                    }
                }
                .coordinateSpace(name: "BillsDashboardView.scroll")
                .listStyle(.plain)
                .appListCompactSpacing()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddBill = true }) {
                    Label("Add Bill", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddBill) {
            BillFormView()
        }
        .alert("Delete Bill?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                billToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let bill = billToDelete {
                    deleteBill(bill)
                }
                billToDelete = nil
            }
        } message: {
            if let bill = billToDelete {
                Text("Are you sure you want to delete \"\(bill.name)\"? This action cannot be undone.")
            }
        }
        .onAppear {
            seedDemoDataIfNeeded()
        }
    }

    // MARK: - Computed Properties

    private var activeBills: [RecurringPurchase] {
        bills.filter { $0.isActive }
    }

    private var activeBillsCount: Int {
        activeBills.count
    }

    private var monthlyTotal: Decimal {
        activeBills.reduce(0) { total, bill in
            total + bill.monthlyEquivalent
        }
    }

    private var upcomingThisWeekCount: Int {
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return activeBills.filter { $0.nextDate <= weekFromNow && $0.nextDate >= Date() }.count
    }

    private var upcomingThisWeekTotal: Decimal {
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return activeBills
            .filter { $0.nextDate <= weekFromNow && $0.nextDate >= Date() }
            .reduce(0) { $0 + $1.amount }
    }

    private var overdueCount: Int {
        activeBills.filter { $0.nextDate < Date() }.count
    }

    private var filteredBills: [RecurringPurchase] {
        switch selectedFilter {
        case .all:
            return bills.filter { $0.isActive }
        case .upcoming:
            let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            return activeBills.filter { $0.nextDate <= weekFromNow && $0.nextDate >= Date() }
        case .overdue:
            return activeBills.filter { $0.nextDate < Date() }
        case .inactive:
            return bills.filter { !$0.isActive }
        }
    }

    // MARK: - Actions

    private func deleteBill(_ bill: RecurringPurchase) {
        modelContext.delete(bill)
        try? modelContext.save()
    }

    private func markAsPaid(_ bill: RecurringPurchase) {
        bill.nextDate = bill.calculateNextOccurrence()
        try? modelContext.save()
    }

    private func toggleActive(_ bill: RecurringPurchase) {
        bill.isActive.toggle()
        try? modelContext.save()
    }

    private func seedDemoDataIfNeeded() {
        guard isDemoMode, !hasCheckedDemoData else { return }
        hasCheckedDemoData = true
        // Demo data for RecurringPurchase is already seeded in DemoDataService
    }
}

// MARK: - Bill Row

struct BillRow: View {
    let bill: RecurringPurchase
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    @State private var showingEditSheet = false

    private var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: bill.nextDate)).day ?? 0
    }

    private var isOverdue: Bool {
        bill.nextDate < Date()
    }

    private var urgencyColor: Color {
        if !bill.isActive {
            return .secondary
        }
        if isOverdue {
            return AppDesign.Colors.danger(for: appColorMode)
        }
        if daysUntilDue <= 3 {
            return AppDesign.Colors.warning(for: appColorMode)
        }
        if daysUntilDue <= 7 {
            return AppDesign.Colors.tint(for: appColorMode)
        }
        return .secondary
    }

    var body: some View {
        Button {
            showingEditSheet = true
        } label: {
            HStack(spacing: AppDesign.Theme.Spacing.medium) {
                // Category Icon
                ZStack {
                    Circle()
                        .fill(urgencyColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: iconForCategory(bill.category))
                        .appDisplayText(AppDesign.Theme.DisplaySize.medium, weight: .regular)
                        .foregroundStyle(urgencyColor)
                }

                // Content
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    HStack {
                        Text(bill.name)
                            .appSectionTitleText()
                            .foregroundStyle(bill.isActive ? .primary : .secondary)

                        if !bill.isActive {
                            Text("Paused")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                        Text(bill.recurrenceFrequency.rawValue)
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        Text(bill.category)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }

                    if bill.isActive {
                        Text(dueDateText)
                            .appCaptionText()
                            .foregroundStyle(urgencyColor)
                    }
                }

                Spacer(minLength: 0)

                // Amount
                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.micro) {
                    Text(bill.amount, format: .currency(code: currencyCode))
                        .appSectionTitleText()
                        .foregroundStyle(bill.isActive ? .primary : .secondary)

                    if bill.recurrenceFrequency != .monthly {
                        Text("\(bill.monthlyEquivalent, format: .currency(code: currencyCode))/mo")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, AppDesign.Theme.Spacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEditSheet) {
            BillFormView(existingBill: bill)
        }
    }

    private var dueDateText: String {
        if isOverdue {
            let daysOverdue = abs(daysUntilDue)
            if daysOverdue == 0 {
                return "Due today"
            } else if daysOverdue == 1 {
                return "1 day overdue"
            } else {
                return "\(daysOverdue) days overdue"
            }
        } else if daysUntilDue == 0 {
            return "Due today"
        } else if daysUntilDue == 1 {
            return "Due tomorrow"
        } else if daysUntilDue <= 7 {
            return "Due in \(daysUntilDue) days"
        } else {
            return "Due \(bill.nextDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "rent", "mortgage", "housing":
            return "house.fill"
        case "utilities", "electricity", "gas", "water":
            return "bolt.fill"
        case "internet", "wifi", "cable":
            return "wifi"
        case "phone", "mobile", "cellphone":
            return "iphone"
        case "insurance":
            return "shield.fill"
        case "subscription", "subscriptions", "streaming":
            return "play.tv.fill"
        case "gym", "fitness":
            return "figure.run"
        case "car", "auto", "vehicle":
            return "car.fill"
        case "loan", "loans", "debt":
            return "creditcard.fill"
        case "healthcare", "health", "medical":
            return "heart.fill"
        default:
            return "calendar.badge.clock"
        }
    }
}

// MARK: - RecurringPurchase Extension

extension RecurringPurchase {
    var monthlyEquivalent: Decimal {
        switch recurrenceFrequency {
        case .weekly:
            return amount * Decimal(52) / Decimal(12)
        case .biweekly:
            return amount * Decimal(26) / Decimal(12)
        case .monthly:
            return amount
        case .quarterly:
            return amount / Decimal(3)
        case .yearly:
            return amount / Decimal(12)
        }
    }
}

#Preview {
    NavigationStack {
        BillsDashboardView()
    }
    .modelContainer(for: [RecurringPurchase.self], inMemory: true)
}
