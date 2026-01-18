import SwiftUI
import SwiftData
import Charts

private extension Transaction {
    var isCategorizedAsIncome: Bool {
        category?.group?.type == .income
    }
}

struct ReviewView: View {
    enum ReportSection: String, CaseIterable {
        case budget = "Budget"
        case income = "Income"
        case expenses = "Expenses"
        case custom = "Custom"
    }
    
    @State private var selectedSection: ReportSection = .budget
    @State private var sharedMonth = Date()
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isTopChromeCompact = false
    @State private var lastScrollOffset: CGFloat = 0

    private var topChromeLargeTitleClearance: CGFloat {
        0
    }

    private var compactThreshold: CGFloat { -80 }
    private var expandThreshold: CGFloat { -20 }

    private var activeScrollKey: String? {
        switch selectedSection {
        case .budget:
            return "BudgetPerformanceView.scroll"
        case .income:
            return "ReportsIncomeView.scroll"
        case .expenses:
            return "ReportsSpendingView.scroll"
        case .custom:
            return "CustomDashboardView.scroll"
        }
    }
    
    var body: some View {
        NavigationStack {
            reviewBody
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        TopChromeTabs(
                            selection: $selectedSection,
                            tabs: ReportSection.allCases.map { .init(id: $0, title: $0.rawValue) },
                            isCompact: isTopChromeCompact
                        )

                        DateRangeFilterHeader(
                            filterMode: $filterMode,
                            date: $sharedMonth,
                            customStartDate: $customStartDate,
                            customEndDate: $customEndDate,
                            isCompact: isTopChromeCompact
                        )
                        .topChromeSegmentedStyle(isCompact: isTopChromeCompact)
                    }
                    .padding(.top, topChromeLargeTitleClearance)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                }
                .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                    let offset = activeScrollKey.flatMap { offsets[$0] } ?? 0
                    lastScrollOffset = offset
                    if !isTopChromeCompact, offset < compactThreshold {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isTopChromeCompact = true
                        }
                    } else if isTopChromeCompact, offset > expandThreshold {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isTopChromeCompact = false
                        }
                    }
                }
                .onChange(of: selectedSection) { _, _ in
                    isTopChromeCompact = false
                }
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
                .withAppLogo()
                .environment(\.demoPillVisible, lastScrollOffset > -20)
        }
    }

    @ViewBuilder
    private var reviewBody: some View {
        Group {
            switch selectedSection {
            case .expenses:
                ReportsSpendingView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .income:
                ReportsIncomeView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .budget:
                BudgetPerformanceView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .custom:
                CustomDashboardView()
            }
        }
        .if(filterMode == .month && selectedSection != .custom) { view in
            view.monthSwipeNavigation(selectedDate: $sharedMonth)
        }
    }
}

private struct MonthlyNetWorthPoint: Identifiable {
    let monthStart: Date
    let value: Decimal
    var id: Date { monthStart }
}

// MARK: - Overview View
	struct ReportsOverviewView: View {
	    @Environment(\.modelContext) private var modelContext
	    @AppStorage("currencyCode") private var currencyCode = "USD"
	    @Query private var accounts: [Account]
	    @Query private var savingsGoals: [SavingsGoal]
	    @Query private var categoryGroups: [CategoryGroup]
	    @Query(sort: \MonthlyAccountTotal.monthStart, order: .reverse) private var monthlyAccountTotals: [MonthlyAccountTotal]

    @Binding var selectedDate: Date
    @State private var showingIncomeExpenseDetail: IncomeExpenseDetail?
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
	    @State private var isRangeHeaderCompact = false
	    @State private var rangeTransactions: [Transaction] = []
	    @State private var accountBalances: [PersistentIdentifier: Decimal] = [:]
	    
	    private var filteredTransactions: [Transaction] {
	        rangeTransactions.filter {
	            $0.kind == .standard &&
            $0.account?.isTrackingOnly != true
        }
    }
    
    private var dateRangeDates: (Date, Date) {
        let calendar = Calendar.current
        switch filterMode {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .year, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .last3Months:
            let end = Date()
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? end
            return (start, end)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return (start, end)
        }
    }
    
    private var totalNetWorth: Decimal {
        netWorthSnapshot.netWorth
    }

    private var totalAssets: Decimal {
        netWorthSnapshot.assets
    }

    private var totalDebt: Decimal {
        netWorthSnapshot.debt
    }

    private struct NetWorthSnapshot {
        let netWorth: Decimal
        let assets: Decimal
        let debt: Decimal
    }

	    private var netWorthSnapshot: NetWorthSnapshot {
	        var netWorth: Decimal = 0
	        var assets: Decimal = 0
	        var debt: Decimal = 0

	        for account in accounts {
	            if account.isTrackingOnly { continue }
	            let balance = accountBalances[account.persistentModelID] ?? account.balance
	            netWorth += balance
	            assets += max(0, balance)
	            debt += abs(min(0, balance))
	        }

	        return NetWorthSnapshot(netWorth: netWorth, assets: assets, debt: debt)
	    }

	    @MainActor
	    private func recomputeAccountBalances(asOf endDate: Date) {
	        let calendar = Calendar.current
	        let endMonthStart = calendar.startOfMonth(for: endDate)

	        // 1) Sum totals after the month that contains endDate (fast, in-memory, single pass).
	        var totalsAfterMonthByAccountID: [PersistentIdentifier: Decimal] = [:]
	        totalsAfterMonthByAccountID.reserveCapacity(max(8, accounts.count))
	        for entry in monthlyAccountTotals {
	            guard entry.monthStart > endMonthStart else { continue }
	            guard let accountID = entry.account?.persistentModelID else { continue }
	            totalsAfterMonthByAccountID[accountID, default: 0] += entry.totalAmount
	        }

	        // 2) For custom ranges, endDate may be mid-month; fetch once for the remainder of that month.
	        let endExclusive = calendar.date(byAdding: .month, value: 1, to: endMonthStart) ?? endDate
	        var partialSameMonthAfterByAccountID: [PersistentIdentifier: Decimal] = [:]

	        // If endDate is effectively end-of-month, skip the fetch.
	        if endDate < endExclusive.addingTimeInterval(-1) {
	            do {
	                let descriptor = FetchDescriptor<Transaction>(
	                    predicate: #Predicate<Transaction> { tx in
	                        tx.date > endDate && tx.date < endExclusive
	                    }
	                )
	                let txs = try modelContext.fetch(descriptor)
	                for tx in txs {
	                    guard let accountID = tx.account?.persistentModelID else { continue }
	                    partialSameMonthAfterByAccountID[accountID, default: 0] += tx.amount
	                }
	            } catch {
	                // fail soft
	            }
	        }

	        var result: [PersistentIdentifier: Decimal] = [:]
	        result.reserveCapacity(max(8, accounts.count))
	        for account in accounts {
	            let id = account.persistentModelID
	            let monthlyAfter = totalsAfterMonthByAccountID[id] ?? 0
	            let partialSameMonthAfter = partialSameMonthAfterByAccountID[id] ?? 0
	            result[id] = account.balance - (monthlyAfter + partialSameMonthAfter)
	        }
	        accountBalances = result
	    }

	    private var monthlyNetWorthSeries: [MonthlyNetWorthPoint] {
	        let calendar = Calendar.current
	        let selectedMonthStart = calendar.startOfMonth(for: dateRangeDates.1)

	        let earliestMonthStart = monthlyAccountTotals.map(\.monthStart).min() ?? selectedMonthStart

	        let monthsAvailable = max(
	            1,
	            (calendar.dateComponents([.month], from: earliestMonthStart, to: selectedMonthStart).month ?? 0) + 1
	        )
	        let monthsToShow = min(12, monthsAvailable)
	        let start = calendar.date(byAdding: .month, value: -(monthsToShow - 1), to: selectedMonthStart) ?? selectedMonthStart

	        var months: [Date] = []
	        months.reserveCapacity(monthsToShow)
	        for offset in 0..<monthsToShow {
	            if let monthStart = calendar.date(byAdding: .month, value: offset, to: start) {
	                months.append(monthStart)
	            }
	        }
	        guard !months.isEmpty else { return [] }

	        let lastShownMonthStart = months.last ?? selectedMonthStart

	        // Build quick lookups of monthly totals by account + month start.
	        var totalsByAccountID: [PersistentIdentifier: [Date: Decimal]] = [:]
	        totalsByAccountID.reserveCapacity(max(8, accounts.count))
	        var totalsAfterLastShownMonthByAccountID: [PersistentIdentifier: Decimal] = [:]

	        for entry in monthlyAccountTotals {
	            guard let accountID = entry.account?.persistentModelID else { continue }
	            if entry.monthStart > lastShownMonthStart {
	                totalsAfterLastShownMonthByAccountID[accountID, default: 0] += entry.totalAmount
	            } else {
	                totalsByAccountID[accountID, default: [:]][entry.monthStart, default: 0] += entry.totalAmount
	            }
	        }

	        // Compute net worth at each month-end using reverse cumulative sums per account.
	        var netWorthByMonthStart: [Date: Decimal] = [:]
	        netWorthByMonthStart.reserveCapacity(months.count)

	        for account in accounts where !account.isTrackingOnly {
	            let id = account.persistentModelID
	            let totals = totalsByAccountID[id] ?? [:]
	            var runningAfter = totalsAfterLastShownMonthByAccountID[id] ?? 0

	            for monthStart in months.reversed() {
	                netWorthByMonthStart[monthStart, default: 0] += (account.balance - runningAfter)
	                runningAfter += totals[monthStart] ?? 0
	            }
	        }

	        return months.map { monthStart in
	            MonthlyNetWorthPoint(monthStart: monthStart, value: netWorthByMonthStart[monthStart] ?? 0)
	        }
	    }
    
    private var periodIncome: Decimal {
        filteredTransactions
            .filter { $0.amount > 0 && $0.isCategorizedAsIncome }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var periodExpenses: Decimal {
        abs(filteredTransactions.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount })
    }
    
    private var netChange: Decimal {
        periodIncome - periodExpenses
    }

    private var savingsRate: Double? {
        guard periodIncome > 0 else { return nil }
        return Double(truncating: (netChange / periodIncome) as NSNumber)
    }

    private var daysInRange: Int {
        let (start, end) = dateRangeDates
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        let days = Calendar.current.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    private var averageDailySpend: Decimal {
        guard !filteredTransactions.isEmpty else { return 0 }
        return periodExpenses / Decimal(daysInRange)
    }

    private var averageDailyIncome: Decimal {
        guard !filteredTransactions.isEmpty else { return 0 }
        return periodIncome / Decimal(daysInRange)
    }

    private var uncategorizedExpenses: [Transaction] {
        filteredTransactions.filter { $0.amount < 0 && $0.category == nil }
    }

    private var uncategorizedCount: Int {
        uncategorizedExpenses.count
    }

    private var uncategorizedAmount: Decimal {
        abs(uncategorizedExpenses.reduce(0) { $0 + $1.amount })
    }

    private var topSpendingCategories: [(name: String, total: Decimal)] {
        var totals: [String: Decimal] = [:]
        for transaction in filteredTransactions where transaction.amount < 0 {
            let name = transaction.category?.name ?? "Uncategorized"
            totals[name, default: 0] += abs(transaction.amount)
        }
        return totals
            .map { (name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var largestExpense: Transaction? {
        filteredTransactions
            .filter { $0.amount < 0 }
            // Most negative amount
            .min(by: { $0.amount < $1.amount })
    }

    private var largestIncome: Transaction? {
        filteredTransactions
            .filter { $0.amount > 0 && $0.isCategorizedAsIncome }
            .max(by: { $0.amount < $1.amount })
    }

    private var spentByCategoryID: [PersistentIdentifier: Decimal] {
        var totals: [PersistentIdentifier: Decimal] = [:]
        for transaction in filteredTransactions where transaction.amount < 0 {
            guard let category = transaction.category else { continue }
            totals[category.persistentModelID, default: 0] += abs(transaction.amount)
        }
        return totals
    }

    private var expenseGroups: [CategoryGroup] {
        categoryGroups.filter { $0.type == .expense }
    }

    private var expenseCategories: [Category] {
        expenseGroups.flatMap { $0.sortedCategories }
    }

    private func spent(for category: Category) -> Decimal {
        spentByCategoryID[category.persistentModelID, default: 0]
    }

    private var budgetAssigned: Decimal {
        expenseCategories.reduce(0) { $0 + $1.assigned }
    }

    private var budgetSpent: Decimal {
        expenseCategories.reduce(0) { $0 + spent(for: $1) }
    }

    private var budgetRemaining: Decimal {
        budgetAssigned - budgetSpent
    }

    private var budgetUtilization: Double? {
        guard budgetAssigned > 0 else { return nil }
        return min(1, Double(truncating: (budgetSpent / budgetAssigned) as NSNumber))
    }

    private var overBudgetCategories: [(category: Category, overBy: Decimal)] {
        expenseCategories.compactMap { category in
            let over = spent(for: category) - category.assigned
            guard over > 0 else { return nil }
            return (category: category, overBy: over)
        }
        .sorted { $0.overBy > $1.overBy }
    }

    private var activeGoals: [SavingsGoal] {
        savingsGoals
            .filter { !$0.isAchieved }
            .sorted { $0.progressPercentage > $1.progressPercentage }
    }

    private var goalsTargetTotal: Decimal {
        activeGoals.reduce(0) { $0 + $1.targetAmount }
    }

    private var goalsCurrentTotal: Decimal {
        activeGoals.reduce(0) { $0 + $1.currentAmount }
    }

    private var goalsProgress: Double? {
        guard goalsTargetTotal > 0 else { return nil }
        return min(1, Double(truncating: (goalsCurrentTotal / goalsTargetTotal) as NSNumber))
    }

    private var healthScore: Int {
        var score = 50

        if let savingsRate {
            if savingsRate >= 0.20 { score += 20 }
            else if savingsRate >= 0.10 { score += 12 }
            else if savingsRate >= 0.00 { score += 6 }
            else { score -= 10 }
        }

        if let utilization = budgetUtilization {
            if utilization <= 0.90 { score += 10 }
            else if utilization <= 1.00 { score += 5 }
            else if utilization <= 1.10 { score -= 8 }
            else { score -= 16 }
        }

        if totalAssets > 0 {
            let debtRatio = Double(truncating: (totalDebt / totalAssets) as NSNumber)
            if debtRatio <= 0.30 { score += 10 }
            else if debtRatio <= 0.60 { score += 5 }
            else { score -= 6 }
        } else if totalDebt > 0 {
            score -= 8
        }

        if uncategorizedCount > 0 { score -= 5 }

        return max(0, min(100, score))
    }

    private var insights: [String] {
        // Use predictive insights engine
        let engine = PredictiveInsightsEngine(modelContext: modelContext)
        let predictiveInsights = engine.generateInsights(
            transactions: filteredTransactions,
            dateRange: dateRangeDates,
            categories: expenseCategories,
            currentIncome: periodIncome,
            currentExpenses: periodExpenses,
            savingsRate: savingsRate,
            currencyCode: currencyCode
        )

        // Convert predictive insights to strings
        var items = predictiveInsights.prefix(4).map { insight in
            "\(insight.title) \(insight.description)"
        }

        // Fall back to basic insights if no predictive insights
        if items.isEmpty {
            if let savingsRate {
                if savingsRate < 0 {
                    items.append("Spending is higher than income in this period.")
                } else if savingsRate < 0.10 {
                    items.append("Savings rate is modest—small cuts can make a big difference.")
                } else {
                    items.append("Savings rate looks strong for this period.")
                }
            } else {
                items.append("No income detected in this period—import or add income to unlock more insights.")
            }

            if uncategorizedCount > 0 {
                items.append("\(uncategorizedCount) uncategorized expense\(uncategorizedCount == 1 ? "" : "s")—categorize to improve your reports.")
            }

            if let topOver = overBudgetCategories.first {
                items.append("Top over-budget category: \(topOver.category.name).")
            } else if budgetAssigned > 0 {
                items.append("No categories are over budget—nice work staying on track.")
            }
        }

        return Array(items.prefix(4))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollOffsetReader(coordinateSpace: "ReportsOverviewView.scroll", id: "ReportsOverviewView.scroll")

                BudgetReviewSectionCard {
                    OverviewHealthCard(
                        score: healthScore,
                        insights: insights,
                        income: periodIncome,
                        expenses: periodExpenses,
                        currencyCode: currencyCode,
                        savingsRate: savingsRate,
                        onTapIncome: { showingIncomeExpenseDetail = .income },
                        onTapExpenses: { showingIncomeExpenseDetail = .expenses }
                    )
                }

                BudgetReviewSectionCard {
                    OverviewNetWorthCard(
                        netWorth: totalNetWorth,
                        assets: totalAssets,
                        debt: totalDebt,
                        accountsCount: accounts.count,
                        currencyCode: currencyCode,
                        series: monthlyNetWorthSeries
                    )
                }

                BudgetReviewSectionCard {
                    OverviewCashFlowCard(
                        income: periodIncome,
                        expenses: periodExpenses,
                        netChange: netChange,
                        averageDailyIncome: averageDailyIncome,
                        averageDailySpend: averageDailySpend,
                        currencyCode: currencyCode,
                        savingsRate: savingsRate
                    )
                }

                BudgetReviewSectionCard {
                    OverviewBudgetHealthCard(
                        assigned: budgetAssigned,
                        spent: budgetSpent,
                        remaining: budgetRemaining,
                        currencyCode: currencyCode,
                        utilization: budgetUtilization,
                        overBudgetCategories: Array(overBudgetCategories.prefix(3))
                    )
                }

                BudgetReviewSectionCard {
                    OverviewTopSpendingCard(
                        totalSpending: periodExpenses,
                        items: Array(topSpendingCategories.prefix(5)),
                        currencyCode: currencyCode
                    )
                }

                BudgetReviewSectionCard {
                    OverviewCategorizationCard(
                        categorizedCount: filteredTransactions.filter { $0.amount < 0 && $0.category != nil }.count,
                        categorizedAmount: topSpendingCategories.filter { $0.name != "Uncategorized" }.reduce(0) { $0 + $1.total },
                        uncategorizedCount: uncategorizedCount,
                        uncategorizedAmount: uncategorizedAmount,
                        currencyCode: currencyCode
                    )
                }

                if !activeGoals.isEmpty {
                    BudgetReviewSectionCard {
                        OverviewGoalsCard(
                            goals: Array(activeGoals.prefix(3)),
                            totalProgress: goalsProgress,
                            currencyCode: currencyCode
                        )
                    }
                }

                BudgetReviewSectionCard {
                    OverviewHighlightsCard(
                        transactionCount: filteredTransactions.count,
                        largestExpense: largestExpense,
                        largestIncome: largestIncome,
                        currencyCode: currencyCode
                    )
                }

                BudgetReviewSectionCard {
                    OverviewDeepDiveLinks(selectedDate: $selectedDate)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .background(
            ReportsRangeTransactionsQuery(
                start: dateRangeDates.0,
                end: dateRangeDates.1
            ) { fetched in
                rangeTransactions = fetched
            }
            .id("\(dateRangeDates.0.timeIntervalSinceReferenceDate)-\(dateRangeDates.1.timeIntervalSinceReferenceDate)")
        )
        .coordinateSpace(name: "ReportsOverviewView.scroll")
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                DateRangeFilterHeader(
                    filterMode: $filterMode,
                    date: $selectedDate,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    isCompact: isRangeHeaderCompact
                )
                .padding(.horizontal, isRangeHeaderCompact ? 12 : 14)
                .padding(.vertical, isRangeHeaderCompact ? 8 : 12)
                .background(
                    RoundedRectangle(cornerRadius: isRangeHeaderCompact ? 18 : 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isRangeHeaderCompact ? 18 : 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 8)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -12
            if shouldCompact != isRangeHeaderCompact {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isRangeHeaderCompact = shouldCompact
                }
            }
        }
        .if(filterMode == .month) { view in
            view.monthSwipeNavigation(selectedDate: $selectedDate)
        }
        .task {
            await MonthlyAccountTotalsService.ensureUpToDateAsync(modelContext: modelContext)
        }
        .task(id: "\(accounts.map(\.persistentModelID).hashValue)-\(monthlyAccountTotals.map(\.persistentModelID).hashValue)-\(Int(dateRangeDates.1.timeIntervalSince1970))") {
            recomputeAccountBalances(asOf: dateRangeDates.1)
        }
        .onReceive(NotificationCenter.default.publisher(for: DataChangeTracker.didChangeNotification)) { _ in
            Task { @MainActor in
                await MonthlyAccountTotalsService.ensureUpToDateAsync(modelContext: modelContext)
            }
        }
        .sheet(item: $showingIncomeExpenseDetail) { detail in
            let items = filteredTransactions
                .filter {
                    switch detail {
                    case .income:
                        return $0.amount > 0 && $0.isCategorizedAsIncome
                    case .expenses:
                        return $0.amount < 0
                    }
                }
                .sorted { $0.date > $1.date }
            IncomeExpenseDetailSheet(
                detail: detail,
                transactions: items,
                currencyCode: currencyCode,
                dateRange: dateRangeDates,
                accounts: accounts,
                categoryGroups: categoryGroups
            )
        }
    }
}

private struct ReportsRangeTransactionsQuery: View {
    @Query private var transactions: [Transaction]
    private let onUpdate: ([Transaction]) -> Void

    init(start: Date, end: Date, onUpdate: @escaping ([Transaction]) -> Void) {
        self.onUpdate = onUpdate
        let kind = TransactionKind.standard.rawValue
        _transactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= start &&
                tx.date <= end &&
                tx.kindRawValue == kind
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    var body: some View {
        let signature = transactions.map(\.persistentModelID).hashValue
        Color.clear
            .task(id: signature) {
                onUpdate(transactions)
            }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }

    func endOfMonth(for date: Date) -> Date {
        let start = startOfMonth(for: date)
        let next = self.date(byAdding: .month, value: 1, to: start) ?? start
        return next.addingTimeInterval(-1)
    }
}

private enum IncomeExpenseDetail: String, Identifiable {
    case income
    case expenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: return "Income"
        case .expenses: return "Expenses"
        }
    }
}

private struct OverviewHealthCard: View {
    let score: Int
    let insights: [String]
    let income: Decimal
    let expenses: Decimal
    let currencyCode: String
    let savingsRate: Double?
    let onTapIncome: () -> Void
    let onTapExpenses: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    private var scoreColor: Color {
        switch score {
        case 0..<45: return AppColors.danger(for: appColorMode)
        case 45..<70: return AppColors.warning(for: appColorMode)
        default: return AppColors.success(for: appColorMode)
        }
    }

    private var scoreLabel: String {
        switch score {
        case 0..<45: return "Needs Attention"
        case 45..<70: return "Stable"
        default: return "Strong"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Financial Health")
                        .font(.headline)

                    Text(scoreLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BudgetReviewRingProgress(progress: Double(score) / 100.0, color: scoreColor)
            }

            HStack(spacing: 10) {
                Button(action: onTapIncome) {
                    OverviewStatChip(
                        icon: "arrow.down.circle.fill",
                        label: "Income",
                        value: income,
                        currencyCode: currencyCode,
                        tint: AppColors.success(for: appColorMode)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onTapExpenses) {
                    OverviewStatChip(
                        icon: "arrow.up.circle.fill",
                        label: "Expenses",
                        value: expenses,
                        currencyCode: currencyCode,
                        tint: AppColors.danger(for: appColorMode)
                    )
                }
                .buttonStyle(.plain)
            }

            if let savingsRate {
                OverviewInlineMeter(
                    title: "Savings Rate",
                    valueText: "\(Int(max(-1, min(1, savingsRate)) * 100))%",
                    progress: max(0, min(1, savingsRate)),
                    tint: savingsRate >= 0.10
                        ? AppColors.success(for: appColorMode)
                        : (savingsRate >= 0 ? AppColors.warning(for: appColorMode) : AppColors.danger(for: appColorMode))
                )
            }

            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Insights")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(insights, id: \.self) { insight in
                        OverviewInsightRow(text: insight)
                    }
                }
            }
        }
    }
}

private struct IncomeExpenseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    let detail: IncomeExpenseDetail
    let transactions: [Transaction]
    let currencyCode: String
    let dateRange: (start: Date, end: Date)
    let accounts: [Account]
    let categoryGroups: [CategoryGroup]

    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var showingFilters = false

    private var filteredTransactions: [Transaction] {
        var filtered = transactions

        if let account = selectedAccount {
            filtered = filtered.filter { $0.account?.persistentModelID == account.persistentModelID }
        }

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category?.persistentModelID == category.persistentModelID }
        }

        return filtered
    }

    private var total: Decimal {
        switch detail {
        case .income:
            return filteredTransactions.reduce(0) { $0 + $1.amount }
        case .expenses:
            return abs(filteredTransactions.reduce(0) { $0 + $1.amount })
        }
    }

    private var hasActiveFilters: Bool {
        selectedAccount != nil || selectedCategory != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.title)
                                .font(.headline)

                            Text(dateRangeTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(total, format: .currency(code: currencyCode))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(detail == .income ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 4)
                }

                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        hasActiveFilters ? "No Matching Transactions" : "No \(detail.title)",
                        systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray",
                        description: Text(hasActiveFilters ? "Try adjusting your filters." : "No \(detail.title.lowercased()) transactions found for this period.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(filteredTransactions) { transaction in
                            NavigationLink {
                                TransactionFormView(transaction: transaction)
                            } label: {
                                OverviewTransactionRow(
                                    transaction: transaction,
                                    currencyCode: currencyCode,
                                    emphasizeOutflow: detail == .expenses
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasActiveFilters ? AppColors.tint(for: appColorMode) : .primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFilters) {
                filterSheet
            }
        }
    }

    private var dateRangeTitle: String {
        let calendar = Calendar.current
        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: dateRange.start)) ?? dateRange.start
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: dateRange.end)) ?? dateRange.end
        if calendar.isDate(startMonth, equalTo: endMonth, toGranularity: .month) {
            return startMonth.formatted(.dateTime.month(.wide).year())
        }
        let startText = startMonth.formatted(.dateTime.month(.abbreviated).year())
        let endText = endMonth.formatted(.dateTime.month(.abbreviated).year())
        return "\(startText) – \(endText)"
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("All Accounts").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(Optional<Category>.none)
                        ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                            ForEach(group.sortedCategories) { category in
                                Text(category.name).tag(Optional(category))
                            }
                        }
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button("Clear All Filters") {
                            selectedAccount = nil
                            selectedCategory = nil
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingFilters = false }
                }
            }
        }
    }
}

private struct OverviewTransactionRow: View {
    let transaction: Transaction
    let currencyCode: String
    let emphasizeOutflow: Bool
    @Environment(\.appColorMode) private var appColorMode

    private var amountColor: Color {
        if transaction.amount >= 0 { return AppColors.success(for: appColorMode) }
        return emphasizeOutflow ? AppColors.danger(for: appColorMode) : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.payee)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if transaction.isTransfer {
                        Text("Transfer")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.tint(for: appColorMode).opacity(0.1)))
                            .foregroundStyle(AppColors.tint(for: appColorMode))
                            .lineLimit(1)
                    } else if let category = transaction.category {
                        Text(category.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Uncategorized")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.12)))
                            .foregroundStyle(AppColors.warning(for: appColorMode))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: currencyCode))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }
}

private struct OverviewNetWorthCard: View {
    let netWorth: Decimal
    let assets: Decimal
    let debt: Decimal
    let accountsCount: Int
    let currencyCode: String
    let series: [MonthlyNetWorthPoint]

    @State private var selectedMonth: Date? = nil
    @Environment(\.appColorMode) private var appColorMode

    private var selectedPoint: MonthlyNetWorthPoint? {
        guard let selectedMonth else { return nil }
        return series.min(by: { abs($0.monthStart.timeIntervalSince(selectedMonth)) < abs($1.monthStart.timeIntervalSince(selectedMonth)) })
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.currencySymbol ?? "$"
    }

    private func compactCurrencyLabel(_ value: Double) -> String {
        let isNegative = value < 0
        let absolute = abs(value)

        let compact = absolute.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
        .replacingOccurrences(of: "K", with: "k")

        if isNegative {
            return "-\(currencySymbol)\(compact)"
        }
        return "\(currencySymbol)\(compact)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Worth")
                        .font(.headline)
                    Text(netWorth, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                OverviewMetricTile(
                    title: "Assets",
                    valueText: assets.formatted(.currency(code: currencyCode)),
                    icon: "building.columns.fill",
                    tint: AppColors.tint(for: appColorMode)
                )
                OverviewMetricTile(
                    title: "Debt",
                    valueText: debt.formatted(.currency(code: currencyCode)),
                    icon: "creditcard.fill",
                    tint: AppColors.warning(for: appColorMode)
                )
                OverviewMetricTile(
                    title: "Accounts",
                    valueText: "\(accountsCount)",
                    icon: "wallet.pass.fill",
                    tint: .purple
                )
            }

            if series.count > 1 {
                Chart(series) { point in
                    LineMark(
                        x: .value("Month", point.monthStart),
                        y: .value("Net Worth", Double(truncating: point.value as NSNumber))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppColors.tint(for: appColorMode))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geo[plotFrame].origin
                                            let locationX = value.location.x - origin.x
                                            if let date: Date = proxy.value(atX: locationX) {
                                                selectedMonth = date
                                            }
                                        }
                                        .onEnded { _ in
                                            // Keep the selection visible after lifting the finger.
                                        }
                                )

                            if let selectedPoint,
                               let plotFrameAnchor = proxy.plotFrame,
                               let xPosition = proxy.position(forX: selectedPoint.monthStart),
                               let yPosition = proxy.position(forY: Double(truncating: selectedPoint.value as NSNumber)) {
                                let plotFrame = geo[plotFrameAnchor]
                                let x = plotFrame.origin.x + xPosition
                                let y = plotFrame.origin.y + yPosition

                                Path { path in
                                    path.move(to: CGPoint(x: x, y: plotFrame.minY))
                                    path.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
                                }
                                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .zIndex(1)

                                Circle()
                                    .fill(AppColors.tint(for: appColorMode))
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                    .position(x: x, y: y)
                                    .zIndex(2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedPoint.monthStart, format: .dateTime.month(.abbreviated).year())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedPoint.value, format: .currency(code: currencyCode))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.systemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                                .offset(x: min(max(0, x - plotFrame.minX - 70), plotFrame.width - 140), y: -8)
                                .zIndex(3)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisTick().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisTick()
                            .foregroundStyle(.secondary.opacity(0.35))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(compactCurrencyLabel(y))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.top, 2)
                .onAppear {
                    selectedMonth = series.last?.monthStart
                }
            }
        }
    }
}

private struct OverviewCashFlowCard: View {
    let income: Decimal
    let expenses: Decimal
    let netChange: Decimal
    let averageDailyIncome: Decimal
    let averageDailySpend: Decimal
    let currencyCode: String
    let savingsRate: Double?
    @Environment(\.appColorMode) private var appColorMode

    private var netColor: Color {
        netChange >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cash Flow")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                OverviewValueTile(
                    title: "Income",
                    value: income,
                    currencyCode: currencyCode,
                    tint: AppColors.success(for: appColorMode)
                )
                OverviewValueTile(
                    title: "Expenses",
                    value: expenses,
                    currencyCode: currencyCode,
                    tint: AppColors.danger(for: appColorMode)
                )
                OverviewValueTile(
                    title: "Net Change",
                    value: netChange,
                    currencyCode: currencyCode,
                    tint: netColor
                )
                OverviewValueTile(
                    title: "Avg / Day Spend",
                    value: averageDailySpend,
                    currencyCode: currencyCode,
                    tint: .secondary
                )
            }

            if let savingsRate {
                OverviewInlineMeter(
                    title: "Budget Buffer",
                    valueText: savingsRate >= 0 ? "Positive" : "Negative",
                    progress: max(0, min(1, savingsRate)),
                    tint: savingsRate >= 0.10
                        ? AppColors.success(for: appColorMode)
                        : (savingsRate >= 0 ? AppColors.warning(for: appColorMode) : AppColors.danger(for: appColorMode))
                )
            }

            Text("Avg / Day Income: \(averageDailyIncome.formatted(.currency(code: currencyCode)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct OverviewBudgetHealthCard: View {
    let assigned: Decimal
    let spent: Decimal
    let remaining: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode
    let utilization: Double?
    let overBudgetCategories: [(category: Category, overBy: Decimal)]

    private var utilizationColor: Color {
        guard let utilization else { return AppColors.tint(for: appColorMode) }
        // Green up to 75%, orange 76-99%, red 100%+
        if utilization <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if utilization < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Budget Health")
                    .font(.headline)

                Spacer()

                if assigned > 0 {
                    Text("\(Int((utilization ?? 0) * 100))% used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if assigned <= 0 {
                ContentUnavailableView(
                    "No Budget Assigned",
                    systemImage: "chart.pie",
                    description: Text("Assign amounts to categories to see budget health here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                OverviewInlineMeter(
                    title: "Spent vs Assigned",
                    valueText: "\(spent.formatted(.currency(code: currencyCode))) of \(assigned.formatted(.currency(code: currencyCode)))",
                    progress: utilization ?? 0,
                    tint: utilizationColor
                )

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    OverviewValueTile(
                        title: "Assigned",
                        value: assigned,
                        currencyCode: currencyCode,
                        tint: .primary
                    )
                    OverviewValueTile(
                        title: "Left",
                        value: remaining,
                        currencyCode: currencyCode,
                        tint: remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode)
                    )
                }

                if !overBudgetCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Over Budget")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(overBudgetCategories, id: \.category.persistentModelID) { item in
                            HStack {
                                Text(item.category.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(item.overBy.formatted(.currency(code: currencyCode)))")
                                    .foregroundStyle(AppColors.danger(for: appColorMode))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewTopSpendingCard: View {
    let totalSpending: Decimal
    let items: [(name: String, total: Decimal)]
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Spending")
                    .font(.headline)

                Spacer()

                Text(totalSpending, format: .currency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if items.isEmpty || totalSpending <= 0 {
                ContentUnavailableView(
                    "Not enough transaction data yet",
                    systemImage: "chart.bar",
                    description: Text("Add transactions to see what categories drive your spending.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(items, id: \.name) { item in
                        let pct = totalSpending > 0 ? Double(truncating: (item.total / totalSpending) as NSNumber) : 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.total, format: .currency(code: currencyCode))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            ProgressView(value: pct)
                                .tint(AppColors.danger(for: appColorMode))
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewCategorizationCard: View {
    let categorizedCount: Int
    let categorizedAmount: Decimal
    let uncategorizedCount: Int
    let uncategorizedAmount: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    private var total: Decimal { categorizedAmount + uncategorizedAmount }

    private var pctCategorized: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(truncating: (categorizedAmount / total) as NSNumber))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Categorization")
                .font(.headline)

            OverviewInlineMeter(
                title: "Categorized Spend",
                valueText: "\(Int(pctCategorized * 100))% categorized",
                progress: pctCategorized,
                tint: uncategorizedCount > 0 ? AppColors.warning(for: appColorMode) : AppColors.success(for: appColorMode)
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                OverviewValueTile(
                    title: "Categorized",
                    value: categorizedAmount,
                    currencyCode: currencyCode,
                    tint: .primary
                )
                OverviewValueTile(
                    title: "Uncategorized",
                    value: uncategorizedAmount,
                    currencyCode: currencyCode,
                    tint: uncategorizedCount > 0 ? AppColors.warning(for: appColorMode) : .secondary
                )
            }

            Text("\(uncategorizedCount) uncategorized expense\(uncategorizedCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OverviewGoalsCard: View {
    let goals: [SavingsGoal]
    let totalProgress: Double?
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Savings Goals")
                    .font(.headline)

                Spacer()

                if let totalProgress {
                    Text("\(Int(totalProgress * 100))% overall")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 12) {
                ForEach(goals, id: \.persistentModelID) { goal in
                    let progress = min(1, max(0, goal.progressPercentage / 100))
                    let fallback = AppColors.tint(for: appColorMode)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: goal.colorHex) ?? fallback)
                                    .frame(width: 10, height: 10)
                                Text(goal.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("\(goal.currentAmount.formatted(.currency(code: currencyCode))) / \(goal.targetAmount.formatted(.currency(code: currencyCode)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        ProgressView(value: progress)
                            .tint(Color(hex: goal.colorHex) ?? fallback)

                        if let targetDate = goal.targetDate {
                            Text("Target: \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewHighlightsCard: View {
    let transactionCount: Int
    let largestExpense: Transaction?
    let largestIncome: Transaction?
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Highlights")
                .font(.headline)

            OverviewInfoRow(
                icon: "list.number",
                title: "Transactions",
                value: "\(transactionCount)"
            )

            if let largestExpense {
                OverviewInfoRow(
                    icon: "arrow.up.right.circle.fill",
                    title: "Largest Expense",
                    value: abs(largestExpense.amount).formatted(.currency(code: currencyCode)),
                    subtitle: largestExpense.payee,
                    tint: AppColors.danger(for: appColorMode)
                )
            }

            if let largestIncome {
                OverviewInfoRow(
                    icon: "arrow.down.left.circle.fill",
                    title: "Largest Income",
                    value: largestIncome.amount.formatted(.currency(code: currencyCode)),
                    subtitle: largestIncome.payee,
                    tint: AppColors.success(for: appColorMode)
                )
            }
        }
    }
}

private struct OverviewDeepDiveLinks: View {
    @Binding var selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deep Dive")
                .font(.headline)

            VStack(spacing: 10) {
                NavigationLink {
                    BudgetPerformanceStandaloneView(selectedDate: $selectedDate)
                } label: {
                    OverviewLinkRow(
                        icon: "chart.pie.fill",
                        title: "Budget",
                        subtitle: "See category-by-category progress"
                    )
                }

                NavigationLink {
                    ReportsIncomeStandaloneView(selectedDate: selectedDate)
                } label: {
                    OverviewLinkRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Income",
                        subtitle: "Track income sources and trends"
                    )
                }

                NavigationLink {
                    ReportsSpendingStandaloneView(selectedDate: selectedDate)
                } label: {
                    OverviewLinkRow(
                        icon: "chart.bar.fill",
                        title: "Expenses",
                        subtitle: "Find what drives your expenses"
                    )
                }

                NavigationLink {
                    CustomDashboardView()
                } label: {
                    OverviewLinkRow(
                        icon: "square.grid.2x2.fill",
                        title: "Custom",
                        subtitle: "Build your own dashboard"
                    )
                }
            }
        }
    }
}

private struct ReportsSpendingStandaloneView: View {
    @State private var selectedDate: Date
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isHeaderCompact = false

    init(selectedDate: Date) {
        _selectedDate = State(initialValue: selectedDate)
    }

    var body: some View {
        ReportsSpendingView(
            selectedDate: $selectedDate,
            filterMode: $filterMode,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            DateRangeFilterHeader(
                filterMode: $filterMode,
                date: $selectedDate,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isCompact: isHeaderCompact
            )
            .padding(.horizontal, isHeaderCompact ? 12 : 14)
            .padding(.vertical, isHeaderCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -12
            if shouldCompact != isHeaderCompact {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHeaderCompact = shouldCompact
                }
            }
        }
        .if(filterMode == .month) { view in
            view.monthSwipeNavigation(selectedDate: $selectedDate)
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ReportsIncomeStandaloneView: View {
    @State private var selectedDate: Date
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isHeaderCompact = false

    init(selectedDate: Date) {
        _selectedDate = State(initialValue: selectedDate)
    }

    var body: some View {
        ReportsIncomeView(
            selectedDate: $selectedDate,
            filterMode: $filterMode,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            DateRangeFilterHeader(
                filterMode: $filterMode,
                date: $selectedDate,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isCompact: isHeaderCompact
            )
            .padding(.horizontal, isHeaderCompact ? 12 : 14)
            .padding(.vertical, isHeaderCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -12
            if shouldCompact != isHeaderCompact {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHeaderCompact = shouldCompact
                }
            }
        }
        .if(filterMode == .month) { view in
            view.monthSwipeNavigation(selectedDate: $selectedDate)
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct BudgetPerformanceStandaloneView: View {
    @Binding var selectedDate: Date
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isHeaderCompact = false

    var body: some View {
        BudgetPerformanceView(
            selectedDate: $selectedDate,
            filterMode: $filterMode,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            DateRangeFilterHeader(
                filterMode: $filterMode,
                date: $selectedDate,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isCompact: isHeaderCompact
            )
            .padding(.horizontal, isHeaderCompact ? 12 : 14)
            .padding(.vertical, isHeaderCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isHeaderCompact ? 18 : 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -12
            if shouldCompact != isHeaderCompact {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHeaderCompact = shouldCompact
                }
            }
        }
        .if(filterMode == .month) { view in
            view.monthSwipeNavigation(selectedDate: $selectedDate)
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct OverviewMetricTile: View {
    let title: String
    let valueText: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(valueText)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OverviewValueTile: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value, format: .currency(code: currencyCode))
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OverviewInlineMeter: View {
    let title: String
    let valueText: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            ProgressView(value: max(0, min(1, progress)))
                .tint(tint)
        }
    }
}

private struct OverviewInsightRow: View {
    let text: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppColors.tint(for: appColorMode))
                .font(.caption)
                .padding(.top, 1)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OverviewStatChip: View {
    let icon: String
    let label: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value, format: .currency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OverviewInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 34)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OverviewLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.tint(for: appColorMode).opacity(0.12))
                Image(systemName: icon)
                    .foregroundStyle(AppColors.tint(for: appColorMode))
                    .font(.headline)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Spending Analysis
struct ReportsSpendingView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    @Binding var selectedDate: Date
    @Binding var filterMode: DateRangeFilterHeader.FilterMode
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var drilldown: ReviewTransactionDrilldown? = nil

    // Use @Query to fetch all standard transactions, then filter in computed property
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "standard"
        },
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var allStandardTransactions: [Transaction]

    // Computed property replaces manual caching - filters by date range and expense type
    private var filteredTransactions: [Transaction] {
        let (start, end) = dateRangeDates
        return allStandardTransactions.filter { tx in
            tx.date >= start &&
            tx.date <= end &&
            tx.amount < 0 &&
            tx.account?.isTrackingOnly != true
        }
    }
    
    private var dateRangeDates: (Date, Date) {
        let calendar = Calendar.current
        switch filterMode {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .year, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .last3Months:
            let end = Date()
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? end
            return (start, end)
        case .custom:
            // Ensure start is start of day, end is end of day
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return (start, end)
        }
    }
    
    private var spendingByCategory: [(String, Decimal)] {
        var categoryTotals: [String: Decimal] = [:]
        filteredTransactions.forEach { transaction in
            let categoryName = transaction.category?.name ?? "Uncategorized"
            categoryTotals[categoryName, default: 0] += abs(transaction.amount)
        }
        return categoryTotals.sorted { $0.value > $1.value }
    }
    
    private var spendingByMerchant: [(String, Decimal)] {
        var merchantTotals: [String: Decimal] = [:]
        filteredTransactions.forEach { transaction in
            let merchant = transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            merchantTotals[merchant.isEmpty ? "Unknown" : merchant, default: 0] += abs(transaction.amount)
        }
        return merchantTotals.sorted { $0.value > $1.value }
    }

    private var daysInRange: Int {
        let calendar = Calendar.current
        let (start, end) = dateRangeDates
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    private var averageDailySpend: Decimal {
        guard totalSpending > 0 else { return 0 }
        return totalSpending / Decimal(daysInRange)
    }

    private var averageExpense: Decimal {
        guard !filteredTransactions.isEmpty else { return 0 }
        return totalSpending / Decimal(filteredTransactions.count)
    }

    private var largestExpense: Transaction? {
        filteredTransactions.min(by: { $0.amount < $1.amount })
    }

    private var uncategorizedAmount: Decimal {
        abs(filteredTransactions.filter { $0.category == nil }.reduce(0) { $0 + $1.amount })
    }

    private var spendingTrend: ReviewTrendSeries {
        ReviewTrendSeries(
            start: dateRangeDates.0,
            end: dateRangeDates.1,
            transactions: filteredTransactions,
            kind: .expenses
        )
    }

    private var totalSpending: Decimal {
        filteredTransactions.reduce(0) { $0 + abs($1.amount) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollOffsetReader(coordinateSpace: "ReportsSpendingView.scroll", id: "ReportsSpendingView.scroll")

                BudgetReviewSectionCard {
                    SpendingSummaryCard(
                        total: totalSpending,
                        transactionCount: filteredTransactions.count,
                        avgDaily: averageDailySpend,
                        avgTransaction: averageExpense,
                        currencyCode: currencyCode,
                        uncategorizedAmount: uncategorizedAmount,
                        largestExpense: largestExpense
                    )
                }

                BudgetReviewSectionCard {
                    MonthlySpendComparisonCard(referenceDate: $selectedDate)
                }

                BudgetReviewSectionCard {
                    ReviewTrendCard(
                        title: "Spending Trend",
                        subtitle: "How spending changes across your selected range",
                        series: spendingTrend,
                        currencyCode: currencyCode,
                        tint: AppColors.danger(for: appColorMode)
                    )
                }

                BudgetReviewSectionCard {
                    ReviewBreakdownCard(
                        title: "Top Categories",
                        subtitle: "Where your money goes",
                        items: Array(spendingByCategory.prefix(8)),
                        total: totalSpending,
                        currencyCode: currencyCode,
                        tint: AppColors.danger(for: appColorMode)
                    ) { name in
                        let matching = filteredTransactions.filter { ($0.category?.name ?? "Uncategorized") == name }.sorted { $0.date > $1.date }
                        drilldown = ReviewTransactionDrilldown(
                            title: name,
                            subtitle: "Expenses",
                            transactions: matching,
                            currencyCode: currencyCode,
                            emphasizeOutflow: true
                        )
                    }
                }

                BudgetReviewSectionCard {
                    ReviewBreakdownCard(
                        title: "Top Merchants",
                        subtitle: "Who you pay most often",
                        items: Array(spendingByMerchant.prefix(8)),
                        total: totalSpending,
                        currencyCode: currencyCode,
                        tint: AppColors.warning(for: appColorMode)
                    ) { merchant in
                        let matching = filteredTransactions.filter { $0.payee.trimmingCharacters(in: .whitespacesAndNewlines) == merchant }.sorted { $0.date > $1.date }
                        drilldown = ReviewTransactionDrilldown(
                            title: merchant,
                            subtitle: "Expenses",
                            transactions: matching,
                            currencyCode: currencyCode,
                            emphasizeOutflow: true
                        )
                    }
                }

                BudgetReviewSectionCard {
                    SpendingInsightsCard(
                        totalSpending: totalSpending,
                        daysInRange: daysInRange,
                        transactionCount: filteredTransactions.count,
                        topCategory: spendingByCategory.first,
                        topMerchant: spendingByMerchant.first,
                        uncategorizedAmount: uncategorizedAmount,
                        currencyCode: currencyCode
                    )
                }

                BudgetReviewSectionCard {
                    Button {
                        drilldown = ReviewTransactionDrilldown(
                            title: "All Expenses",
                            subtitle: ReviewTrendSeries.subtitleText(for: dateRangeDates),
                            transactions: filteredTransactions.sorted { $0.date > $1.date },
                            currencyCode: currencyCode,
                            emphasizeOutflow: true
                        )
                    } label: {
                        OverviewLinkRow(
                            icon: "list.bullet",
                            title: "View Expense Transactions",
                            subtitle: "Browse and verify all expenses in this range"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(name: "ReportsSpendingView.scroll")
        .sheet(item: $drilldown) { drilldown in
            ReviewTransactionsSheet(drilldown: drilldown)
        }
        // No manual refresh needed - @Query automatically updates when data changes
    }
}

// MARK: - Income Trends
struct ReportsIncomeView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    @Binding var selectedDate: Date
    @Binding var filterMode: DateRangeFilterHeader.FilterMode
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var drilldown: ReviewTransactionDrilldown? = nil

    // Use @Query to fetch all standard transactions, then filter in computed property
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "standard"
        },
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var allStandardTransactions: [Transaction]

    // Computed property replaces manual caching - filters by date range and income type
    private var filteredTransactions: [Transaction] {
        let (start, end) = dateRangeDates
        return allStandardTransactions.filter { tx in
            tx.date >= start &&
            tx.date <= end &&
            tx.amount > 0 &&
            tx.isCategorizedAsIncome &&
            tx.account?.isTrackingOnly != true
        }
    }
    
    private var dateRangeDates: (Date, Date) {
        let calendar = Calendar.current
        switch filterMode {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .year, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .last3Months:
            let end = Date()
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? end
            return (start, end)
        case .custom:
            // Ensure start is start of day, end is end of day
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return (start, end)
        }
    }
    
    private var totalIncome: Decimal {
        filteredTransactions.reduce(0) { $0 + $1.amount }
    }

    private var incomeBySource: [(String, Decimal)] {
        var sourceTotals: [String: Decimal] = [:]
        filteredTransactions.forEach { transaction in
            let source = transaction.category?.name ?? transaction.payee
            sourceTotals[source, default: 0] += transaction.amount
        }
        return sourceTotals.sorted { $0.value > $1.value }
    }

    private var incomeByPayer: [(String, Decimal)] {
        var totals: [String: Decimal] = [:]
        filteredTransactions.forEach { transaction in
            let payer = transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            totals[payer.isEmpty ? "Unknown" : payer, default: 0] += transaction.amount
        }
        return totals.sorted { $0.value > $1.value }
    }

    private var daysInRange: Int {
        let calendar = Calendar.current
        let (start, end) = dateRangeDates
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    private var averageDailyIncome: Decimal {
        guard totalIncome > 0 else { return 0 }
        return totalIncome / Decimal(daysInRange)
    }

    private var averageDeposit: Decimal {
        guard !filteredTransactions.isEmpty else { return 0 }
        return totalIncome / Decimal(filteredTransactions.count)
    }

    private var largestIncome: Transaction? {
        filteredTransactions.max(by: { $0.amount < $1.amount })
    }

    private var payerConcentration: Double? {
        guard let top = incomeByPayer.first, totalIncome > 0 else { return nil }
        return Double(truncating: (top.1 / totalIncome) as NSNumber)
    }

    private var incomeTrend: ReviewTrendSeries {
        ReviewTrendSeries(
            start: dateRangeDates.0,
            end: dateRangeDates.1,
            transactions: filteredTransactions,
            kind: .income
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollOffsetReader(coordinateSpace: "ReportsIncomeView.scroll", id: "ReportsIncomeView.scroll")

                BudgetReviewSectionCard {
                    IncomeSummaryCard(
                        total: totalIncome,
                        transactionCount: filteredTransactions.count,
                        avgDaily: averageDailyIncome,
                        avgDeposit: averageDeposit,
                        currencyCode: currencyCode,
                        largestIncome: largestIncome,
                        payerConcentration: payerConcentration
                    )
                }

                BudgetReviewSectionCard {
                    MonthlyIncomeComparisonCard(referenceDate: $selectedDate)
                }

                BudgetReviewSectionCard {
                    ReviewTrendCard(
                        title: "Income Trend",
                        subtitle: "How income changes across your selected range",
                        series: incomeTrend,
                        currencyCode: currencyCode,
                        tint: AppColors.success(for: appColorMode)
                    )
                }

                BudgetReviewSectionCard {
                    ReviewBreakdownCard(
                        title: "Top Payers",
                        subtitle: "Where your income comes from",
                        items: Array(incomeByPayer.prefix(8)),
                        total: totalIncome,
                        currencyCode: currencyCode,
                        tint: AppColors.success(for: appColorMode)
                    ) { payer in
                        let matching = filteredTransactions.filter { $0.payee.trimmingCharacters(in: .whitespacesAndNewlines) == payer }.sorted { $0.date > $1.date }
                        drilldown = ReviewTransactionDrilldown(
                            title: payer,
                            subtitle: "Income",
                            transactions: matching,
                            currencyCode: currencyCode,
                            emphasizeOutflow: false
                        )
                    }
                }

                if !incomeBySource.isEmpty {
                    BudgetReviewSectionCard {
                        ReviewBreakdownCard(
                            title: "By Category",
                            subtitle: "If you track income categories",
                            items: Array(incomeBySource.prefix(6)),
                            total: totalIncome,
                            currencyCode: currencyCode,
                            tint: AppColors.tint(for: appColorMode)
                        ) { source in
                            let matching = filteredTransactions.filter { ($0.category?.name ?? $0.payee) == source }.sorted { $0.date > $1.date }
                            drilldown = ReviewTransactionDrilldown(
                                title: source,
                                subtitle: "Income",
                                transactions: matching,
                                currencyCode: currencyCode,
                                emphasizeOutflow: false
                            )
                        }
                    }
                }

                BudgetReviewSectionCard {
                    IncomeInsightsCard(
                        totalIncome: totalIncome,
                        daysInRange: daysInRange,
                        transactionCount: filteredTransactions.count,
                        topPayer: incomeByPayer.first,
                        payerConcentration: payerConcentration,
                        currencyCode: currencyCode
                    )
                }

                BudgetReviewSectionCard {
                    Button {
                        drilldown = ReviewTransactionDrilldown(
                            title: "All Income",
                            subtitle: ReviewTrendSeries.subtitleText(for: dateRangeDates),
                            transactions: filteredTransactions.sorted { $0.date > $1.date },
                            currencyCode: currencyCode,
                            emphasizeOutflow: false
                        )
                    } label: {
                        OverviewLinkRow(
                            icon: "list.bullet",
                            title: "View Income Transactions",
                            subtitle: "Browse and verify all income in this range"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(name: "ReportsIncomeView.scroll")
        .sheet(item: $drilldown) { drilldown in
            ReviewTransactionsSheet(drilldown: drilldown)
        }
        // No manual refresh needed - @Query automatically updates when data changes
    }
}

private struct ReviewTransactionDrilldown: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let transactions: [Transaction]
    let currencyCode: String
    let emphasizeOutflow: Bool
}

private struct ReviewTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    let drilldown: ReviewTransactionDrilldown

    private var total: Decimal {
        if drilldown.emphasizeOutflow {
            return abs(drilldown.transactions.reduce(0) { $0 + $1.amount })
        }
        return drilldown.transactions.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drilldown.title)
                                .font(.headline)
                            Text(drilldown.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(total, format: .currency(code: drilldown.currencyCode))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(drilldown.emphasizeOutflow ? AppColors.danger(for: appColorMode) : AppColors.success(for: appColorMode))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 4)
                }

                if drilldown.transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text("Nothing matched this selection.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(drilldown.transactions) { transaction in
                            OverviewTransactionRow(
                                transaction: transaction,
                                currencyCode: drilldown.currencyCode,
                                emphasizeOutflow: drilldown.emphasizeOutflow
                            )
                        }
                    }
                }
            }
            .navigationTitle(drilldown.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum ReviewTrendKind {
    case expenses
    case income
}

private struct ReviewTrendSeries {
    enum Granularity {
        case day, week, month
    }

    struct Bucket: Identifiable {
        let start: Date
        let label: String
        let total: Decimal
        var id: Date { start }
    }

    let start: Date
    let end: Date
    let buckets: [Bucket]
    let granularity: Granularity

    init(start: Date, end: Date, transactions: [Transaction], kind: ReviewTrendKind) {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0

        let granularity: Granularity
        if days <= 31 { granularity = .day }
        else if days <= 180 { granularity = .week }
        else { granularity = .month }

        var totals: [Date: Decimal] = [:]
        for transaction in transactions {
            let bucketStart: Date
            switch granularity {
            case .day:
                bucketStart = calendar.startOfDay(for: transaction.date)
            case .week:
                bucketStart = calendar.dateInterval(of: .weekOfYear, for: transaction.date)?.start ?? calendar.startOfDay(for: transaction.date)
            case .month:
                let comps = calendar.dateComponents([.year, .month], from: transaction.date)
                bucketStart = calendar.date(from: comps) ?? calendar.startOfDay(for: transaction.date)
            }

            let value: Decimal
            switch kind {
            case .expenses:
                value = abs(transaction.amount)
            case .income:
                value = transaction.amount
            }

            totals[bucketStart, default: 0] += value
        }

        let formatter = DateFormatter()
        switch granularity {
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
        }

        self.start = start
        self.end = end
        self.granularity = granularity

        let bucketStarts: [Date] = {
            switch granularity {
            case .day:
                var current = startDay
                var dates: [Date] = []
                while current <= endDay {
                    dates.append(current)
                    current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(24 * 60 * 60)
                }
                return dates
            case .week:
                let startWeek = calendar.dateInterval(of: .weekOfYear, for: startDay)?.start ?? startDay
                let endWeek = calendar.dateInterval(of: .weekOfYear, for: endDay)?.start ?? endDay
                var current = startWeek
                var dates: [Date] = []
                while current <= endWeek {
                    dates.append(current)
                    current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current.addingTimeInterval(7 * 24 * 60 * 60)
                }
                return dates
            case .month:
                let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDay)) ?? startDay
                let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDay)) ?? endDay
                var current = startMonth
                var dates: [Date] = []
                while current <= endMonth {
                    dates.append(current)
                    current = calendar.date(byAdding: .month, value: 1, to: current) ?? current.addingTimeInterval(31 * 24 * 60 * 60)
                }
                return dates
            }
        }()

        self.buckets = bucketStarts.map { date in
            Bucket(start: date, label: formatter.string(from: date), total: totals[date, default: 0])
        }
    }

    static func subtitleText(for range: (Date, Date)) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: range.0)) – \(formatter.string(from: range.1))"
    }
}

private struct ReviewTrendCard: View {
    let title: String
    let subtitle: String
    let series: ReviewTrendSeries
    let currencyCode: String
    let tint: Color

    private var maxValue: Decimal {
        series.buckets.map(\.total).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if maxValue > 0 {
                    Text("Peak \(maxValue.formatted(.currency(code: currencyCode)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if series.buckets.isEmpty || maxValue <= 0 {
                ContentUnavailableView(
                    "Not enough data",
                    systemImage: "chart.bar",
                    description: Text("Add transactions in this range to see a trend.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                Chart(series.buckets) { bucket in
                    BarMark(
                        x: .value("Date", bucket.start),
                        y: .value("Total", NSDecimalNumber(decimal: bucket.total).doubleValue)
                    )
                    .foregroundStyle(tint.gradient)
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                switch series.granularity {
                                case .day:
                                    Text(dateValue, format: .dateTime.month(.abbreviated).day())
                                case .week:
                                    Text(dateValue, format: .dateTime.month(.abbreviated).day())
                                case .month:
                                    Text(dateValue, format: .dateTime.month(.abbreviated))
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ReviewBreakdownCard: View {
    let title: String
    let subtitle: String
    let items: [(String, Decimal)]
    let total: Decimal
    let currencyCode: String
    let tint: Color
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty || total <= 0 {
                ContentUnavailableView(
                    "Not enough data",
                    systemImage: "tray",
                    description: Text("Add transactions to populate this breakdown.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(items, id: \.0) { item in
                        let pct = total > 0 ? Double(truncating: (item.1 / total) as NSNumber) : 0
                        Button {
                            onSelect(item.0)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.0)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(item.1, format: .currency(code: currencyCode))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(tint)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }

                                ProgressView(value: pct)
                                    .tint(tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SpendingSummaryCard: View {
    let total: Decimal
    let transactionCount: Int
    let avgDaily: Decimal
    let avgTransaction: Decimal
    let currencyCode: String
    let uncategorizedAmount: Decimal
    let largestExpense: Transaction?
    @Environment(\.appColorMode) private var appColorMode

    private var uncategorizedShare: Double {
        guard total > 0, uncategorizedAmount > 0 else { return 0 }
        return Double(truncating: (uncategorizedAmount / total) as NSNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spending")
                        .font(.headline)
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.danger(for: appColorMode))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Text("\(transactionCount) tx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                OverviewValueTile(title: "Avg / Day", value: avgDaily, currencyCode: currencyCode, tint: .secondary)
                OverviewValueTile(title: "Avg / Tx", value: avgTransaction, currencyCode: currencyCode, tint: .secondary)
            }

            if uncategorizedAmount > 0 {
                OverviewInlineMeter(
                    title: "Uncategorized",
                    valueText: "\(uncategorizedAmount.formatted(.currency(code: currencyCode))) • \(Int(uncategorizedShare * 100))%",
                    progress: uncategorizedShare,
                    tint: AppColors.warning(for: appColorMode)
                )
            }

            if let largestExpense {
                OverviewInfoRow(
                    icon: "arrow.up.right.circle.fill",
                    title: "Largest Expense",
                    value: abs(largestExpense.amount).formatted(.currency(code: currencyCode)),
                    subtitle: largestExpense.payee,
                    tint: AppColors.danger(for: appColorMode)
                )
            }
        }
    }
}

private struct SpendingInsightsCard: View {
    let totalSpending: Decimal
    let daysInRange: Int
    let transactionCount: Int
    let topCategory: (String, Decimal)?
    let topMerchant: (String, Decimal)?
    let uncategorizedAmount: Decimal
    let currencyCode: String

    private var insights: [String] {
        var items: [String] = []
        if transactionCount == 0 {
            return ["Add expenses in this range to see insights."]
        }

        items.append("Average spend is \( (totalSpending / Decimal(max(1, daysInRange))).formatted(.currency(code: currencyCode)) ) per day.")

        if let topCategory, totalSpending > 0 {
            let pct = Int((Double(truncating: (topCategory.1 / totalSpending) as NSNumber)) * 100)
            items.append("Top category is \(topCategory.0) (\(pct)% of spending).")
        }

        if let topMerchant {
            items.append("Top merchant is \(topMerchant.0).")
        }

        if uncategorizedAmount > 0 {
            items.append("Categorize \(uncategorizedAmount.formatted(.currency(code: currencyCode))) to improve reporting accuracy.")
        }

        return Array(items.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(insights, id: \.self) { text in
                    ReviewStoryCard(
                        title: "Spending",
                        text: text,
                        systemImage: "sparkles",
                        tint: .secondary
                    )
                }
            }
        }
    }
}

private struct IncomeSummaryCard: View {
    let total: Decimal
    let transactionCount: Int
    let avgDaily: Decimal
    let avgDeposit: Decimal
    let currencyCode: String
    let largestIncome: Transaction?
    let payerConcentration: Double?
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Income")
                        .font(.headline)
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.success(for: appColorMode))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Text("\(transactionCount) tx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                OverviewValueTile(title: "Avg / Day", value: avgDaily, currencyCode: currencyCode, tint: .secondary)
                OverviewValueTile(title: "Avg / Deposit", value: avgDeposit, currencyCode: currencyCode, tint: .secondary)
            }

            if let payerConcentration {
                OverviewInlineMeter(
                    title: "Top payer share",
                    valueText: "\(Int(payerConcentration * 100))%",
                    progress: payerConcentration,
                    tint: payerConcentration >= 0.75
                        ? AppColors.warning(for: appColorMode)
                        : AppColors.success(for: appColorMode)
                )
            }

            if let largestIncome {
                OverviewInfoRow(
                    icon: "arrow.down.left.circle.fill",
                    title: "Largest Income",
                    value: largestIncome.amount.formatted(.currency(code: currencyCode)),
                    subtitle: largestIncome.payee,
                    tint: AppColors.success(for: appColorMode)
                )
            }
        }
    }
}

private struct IncomeInsightsCard: View {
    let totalIncome: Decimal
    let daysInRange: Int
    let transactionCount: Int
    let topPayer: (String, Decimal)?
    let payerConcentration: Double?
    let currencyCode: String

    private var insights: [String] {
        var items: [String] = []
        if transactionCount == 0 {
            return ["Add income transactions in this range to see insights."]
        }

        items.append("Average income is \( (totalIncome / Decimal(max(1, daysInRange))).formatted(.currency(code: currencyCode)) ) per day.")

        if let topPayer, let payerConcentration {
            items.append("Top payer is \(topPayer.0) (\(Int(payerConcentration * 100))% of income).")
        } else if let topPayer {
            items.append("Top payer is \(topPayer.0).")
        }

        if transactionCount >= 2 {
            items.append("You received income \(transactionCount) time\(transactionCount == 1 ? "" : "s") in this range.")
        }

        return Array(items.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(insights, id: \.self) { text in
                    ReviewStoryCard(
                        title: "Income",
                        text: text,
                        systemImage: "sparkles",
                        tint: .secondary
                    )
                }
            }
        }
    }
}

private struct ReviewStoryCard: View {
    let title: String
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
        }
        .appCardSurface()
    }
}

// MARK: - Budget Performance
struct BudgetPerformanceView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Query private var categoryGroups: [CategoryGroup]
    @Environment(\.modelContext) private var modelContext

	@Binding var selectedDate: Date
	@Binding var filterMode: DateRangeFilterHeader.FilterMode
	@Binding var customStartDate: Date
	@Binding var customEndDate: Date
	@State private var selectedCategory: Category?

    // Use @Query to fetch all standard transactions, then filter in computed property
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "standard"
        },
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var allStandardTransactions: [Transaction]

    // Computed property replaces manual caching - filters by date range
    private var transactionsInRange: [Transaction] {
        let (start, end) = dateRangeDates
        return allStandardTransactions.filter { tx in
            tx.date >= start &&
            tx.date <= end &&
            tx.account?.isTrackingOnly != true
        }
    }

    private var expenseGroups: [CategoryGroup] {
        categoryGroups.filter { $0.type == .expense }
    }
    
    private var dateRangeDates: (Date, Date) {
        let calendar = Calendar.current
        switch filterMode {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .year, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .last3Months:
            let end = Date()
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? end
            return (start, end)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return (start, end)
        }
    }
    
    private func transactionsFor(category: Category) -> [Transaction] {
        transactionsInRange.filter { $0.category?.id == category.id }
    }
    
    private func activityFor(category: Category) -> Decimal {
        let net = transactionsFor(category: category).reduce(Decimal.zero) { $0 + $1.amount }
        return max(Decimal.zero, -net)
    }
    
    private func groupActivity(_ group: CategoryGroup) -> Decimal {
        group.sortedCategories.reduce(0) { $0 + activityFor(category: $1) }
    }
    
    private func groupAssigned(_ group: CategoryGroup) -> Decimal {
        group.sortedCategories.reduce(0) { $0 + $1.assigned }
    }

    private var totalAssigned: Decimal {
        expenseGroups.reduce(0) { $0 + groupAssigned($1) }
    }

    private var totalSpent: Decimal {
        expenseGroups.reduce(0) { $0 + groupActivity($1) }
    }

    private var totalRemaining: Decimal {
        totalAssigned - totalSpent
    }

    private var daysProgress: (totalDays: Int, daysElapsed: Int, daysRemaining: Int)? {
        let start = dateRangeDates.0
        let end = dateRangeDates.1

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= startDay else { return nil }

        let totalDays = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let clampedNow = min(max(Date(), start), end)
        let elapsed = (calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: clampedNow)).day ?? 0) + 1
        let daysElapsed = max(1, min(totalDays, elapsed))
        let remaining = max(0, totalDays - daysElapsed)
        return (totalDays, daysElapsed, remaining)
    }

    private var projectedTotalSpent: Decimal? {
        guard let progress = daysProgress else { return nil }
        guard progress.daysElapsed > 0 else { return nil }
        let daily = totalSpent / Decimal(progress.daysElapsed)
        return daily * Decimal(progress.totalDays)
    }

    private var overBudgetCategories: [(category: Category, overBy: Decimal, utilization: Double)] {
        var items: [(category: Category, overBy: Decimal, utilization: Double)] = []
        for group in expenseGroups {
            for category in group.sortedCategories {
                let assigned = max(0, category.assigned)
                guard assigned > 0 else { continue }
                let spent = activityFor(category: category)
                let over = spent - assigned
                if over > 0 {
                    let util = Double(truncating: (spent / assigned) as NSNumber)
                    items.append((category: category, overBy: over, utilization: util))
                }
            }
        }
        return items.sorted { a, b in
            if a.overBy != b.overBy { return a.overBy > b.overBy }
            return a.category.name < b.category.name
        }
    }

    private var topOverBudgetCategory: (category: Category, overBy: Decimal)? {
        overBudgetCategories.first.map { ($0.category, $0.overBy) }
    }

    private var biggestLeftCategory: (category: Category, left: Decimal)? {
        var best: (Category, Decimal)? = nil
        for group in expenseGroups {
            for category in group.sortedCategories {
                let assigned = max(0, category.assigned)
                guard assigned > 0 else { continue }
                let left = assigned - activityFor(category: category)
                guard left > 0 else { continue }
                if best == nil || left > (best?.1 ?? 0) {
                    best = (category, left)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    private var budgetPeriodLabel: String {
        let formatter = DateFormatter()
        switch filterMode {
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .last3Months:
            return "Last 3 Months"
        case .year:
            return selectedDate.formatted(.dateTime.year())
        case .custom:
            formatter.dateStyle = .short
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
    }

    private var hasBudgetGroups: Bool {
        !expenseGroups.isEmpty
    }

    private var hasBudgetData: Bool {
        totalAssigned > 0 || totalSpent > 0
    }

    private var shouldShowBudgetDetails: Bool {
        hasBudgetGroups && hasBudgetData
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollOffsetReader(coordinateSpace: "BudgetPerformanceView.scroll", id: "BudgetPerformanceView.scroll")

                BudgetReviewSectionCard {
                    BudgetReviewSummaryCard(
                        currencyCode: currencyCode,
                        periodLabel: budgetPeriodLabel,
                        assigned: totalAssigned,
                        spent: totalSpent,
                        remaining: totalRemaining
                    )
                }

                if shouldShowBudgetDetails {
                    BudgetReviewSectionCard {
                        BudgetInsightsCard(
                            currencyCode: currencyCode,
                            assigned: totalAssigned,
                            spent: totalSpent,
                            projectedSpent: projectedTotalSpent,
                            daysRemaining: daysProgress?.daysRemaining,
                            overBudgetCount: overBudgetCategories.count,
                            topOverBudget: topOverBudgetCategory,
                            biggestLeft: biggestLeftCategory
                        )
                    }

                    ForEach(expenseGroups) { group in
                        let assigned = groupAssigned(group)
                        let spent = groupActivity(group)
                        let remaining = assigned - spent

                        BudgetReviewSectionCard {
                            BudgetReviewGroupCardHeader(
                                groupName: group.name,
                                assigned: assigned,
                                spent: spent,
                                remaining: remaining,
                                currencyCode: currencyCode
                            )

                            VStack(spacing: 0) {
                                ForEach(Array(group.sortedCategories.enumerated()), id: \.element.persistentModelID) { index, category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        BudgetProgressRow(
                                            category: category,
                                            activity: activityFor(category: category),
                                            transactionCount: transactionsFor(category: category).count
                                        )
                                        .padding(.vertical, 2)
                                    }
                                    .buttonStyle(.plain)

                                    if index != group.sortedCategories.count - 1 {
                                        Divider()
                                            .padding(.leading, 52)
                                            .opacity(0.35)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                } else {
                    BudgetReviewSectionCard {
                        BudgetInsightsEmptyStateCard(hasBudgetGroups: hasBudgetGroups)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .coordinateSpace(name: "BudgetPerformanceView.scroll")
        .sheet(item: $selectedCategory) { category in
            CategoryTransactionsSheet(
                category: category,
                transactions: transactionsFor(category: category),
                dateRange: dateRangeDates
            )
        }
        .background(Color(.systemGroupedBackground))
        // No manual refresh needed - @Query automatically updates when data changes
    }
}

private struct BudgetInsightsEmptyStateCard: View {
    let hasBudgetGroups: Bool

    var body: some View {
        ContentUnavailableView(
            hasBudgetGroups ? "No Budget Data Yet" : "No Budget Yet",
            systemImage: "sparkles",
            description: Text(
                hasBudgetGroups
                ? "Assign monthly amounts and add transactions to start seeing progress and insights."
                : "Add budget categories and assign monthly amounts to start tracking progress here."
            )
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct BudgetReviewSectionCard<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .appCardSurface()
    }
}

private struct BudgetReviewSummaryCard: View {
    let currencyCode: String
    let periodLabel: String
    let assigned: Decimal
    let spent: Decimal
    let remaining: Decimal
    @Environment(\.appColorMode) private var appColorMode

    private var progress: Double {
        guard assigned > 0 else { return 0 }
        return min(1, Double(truncating: (spent / assigned) as NSNumber))
    }

    private var progressColor: Color {
        if assigned <= 0 { return AppColors.tint(for: appColorMode) }

        // Green up to 75%, orange 76-99%, red 100%+
        if progress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if progress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget Review")
                        .font(.headline)

                    Text(periodLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BudgetReviewRingProgress(progress: progress, color: progressColor)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BudgetReviewMetricTile(
                    title: "Assigned",
                    value: assigned,
                    currencyCode: currencyCode,
                    valueColor: .primary
                )
                BudgetReviewMetricTile(
                    title: "Spent",
                    value: spent,
                    currencyCode: currencyCode,
                    valueColor: .secondary
                )
                BudgetReviewMetricTile(
                    title: "Left",
                    value: remaining,
                    currencyCode: currencyCode,
                    valueColor: remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode)
                )
            }
        }
    }
}

private struct BudgetInsightsCard: View {
    let currencyCode: String
    let assigned: Decimal
    let spent: Decimal
    let projectedSpent: Decimal?
    let daysRemaining: Int?
    let overBudgetCount: Int
    let topOverBudget: (category: Category, overBy: Decimal)?
    let biggestLeft: (category: Category, left: Decimal)?

    private var insights: [String] {
        guard assigned > 0 || spent > 0 else {
            return ["No insights yet. Assign monthly amounts to start tracking progress and projections."]
        }

        var items: [String] = []

        if assigned > 0 {
            let used = min(2.0, Double(truncating: (spent / assigned) as NSNumber))
            items.append("You’ve used \(Int(used * 100))% of your assigned budget so far.")
        }

        if let projectedSpent, assigned > 0, let daysRemaining, daysRemaining > 0 {
            if projectedSpent > assigned {
                let over = projectedSpent - assigned
                items.append("At this pace, you’re on track to overspend by \(over.formatted(.currency(code: currencyCode))).")
            } else {
                let cushion = assigned - projectedSpent
                items.append("At this pace, you’d finish with about \(cushion.formatted(.currency(code: currencyCode))) left.")
            }
        }

        if overBudgetCount > 0 {
            if let topOverBudget {
                items.append("Top over-budget: \(topOverBudget.category.name) by \(topOverBudget.overBy.formatted(.currency(code: currencyCode))).")
            } else {
                items.append("\(overBudgetCount) categor\(overBudgetCount == 1 ? "y is" : "ies are") over budget.")
            }
        } else if assigned > 0 {
            items.append("No categories are over budget — nice work staying on track.")
        }

        if let biggestLeft {
            items.append("Most budget left: \(biggestLeft.category.name) (\(biggestLeft.left.formatted(.currency(code: currencyCode))) remaining).")
        }

        return Array(items.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(insights, id: \.self) { text in
                    ReviewStoryCard(
                        title: "Budget",
                        text: text,
                        systemImage: "sparkles",
                        tint: .secondary
                    )
                }
            }
        }
    }
}

private struct BudgetReviewMetricTile: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value, format: .currency(code: currencyCode))
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct BudgetReviewRingProgress: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 54, height: 54)
        .accessibilityLabel("Budget used \(Int(progress * 100)) percent")
    }
}

private struct BudgetReviewGroupCardHeader: View {
    let groupName: String
    let assigned: Decimal
    let spent: Decimal
    let remaining: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    private var progress: Double {
        guard assigned > 0 else { return 0 }
        return min(1, Double(truncating: (spent / assigned) as NSNumber))
    }

    private var progressColor: Color {
        if assigned <= 0 { return AppColors.tint(for: appColorMode) }

        // Green up to 75%, orange 76-99%, red 100%+
        if progress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if progress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

	    private var spentPill: some View {
	        BudgetReviewMetricPill(
	            text: Text("Spent: \(spent.formatted(.currency(code: currencyCode)))"),
	            tint: .secondary
	        )
	    }

	    private var leftPill: some View {
	        BudgetReviewMetricPill(
	            text: Text("Left: \(remaining.formatted(.currency(code: currencyCode)))"),
	            tint: remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode)
	        )
	    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            spentPill
            leftPill
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(groupName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ViewThatFits(in: .horizontal) {
                pillsRow

                VStack(alignment: .leading, spacing: 6) {
                    spentPill
                    leftPill
                }
            }

            ProgressView(value: progress)
                .tint(progressColor)
        }
    }
}

private struct BudgetReviewMetricPill: View {
    let text: Text
    let tint: Color

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .monospacedDigit()
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
    }
}

struct BudgetProgressRow: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    let category: Category
    let activity: Decimal
    let transactionCount: Int
    
    private var isIncome: Bool {
        category.group?.type == .income
    }
    
    private var remaining: Decimal {
        category.assigned - activity
    }
    
    private var percentageRemaining: Double {
        guard category.assigned > 0 else { return activity > 0 ? 0 : 1 }
        return max(0, min(1, Double(truncating: remaining as NSNumber) / Double(truncating: category.assigned as NSNumber)))
    }
    
    private var percentageProgress: Double {
        guard category.assigned > 0 else { return activity > 0 ? 1 : 0 }
        return min(1, Double(truncating: activity as NSNumber) / Double(truncating: category.assigned as NSNumber))
    }
    
    private var progressColor: Color {
        if isIncome {
            return AppColors.tint(for: appColorMode)
        }

        // Green up to 75%, orange 76-99%, red 100%+
        if percentageProgress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if percentageProgress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Circle()
                .fill(progressColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(category.icon ?? String(category.name.prefix(1)).uppercased())
                        .font(.system(size: category.icon != nil ? 20 : 16, weight: .semibold))
                        .foregroundColor(progressColor)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if transactionCount > 0 {
                        Text("\(transactionCount)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(Color(.systemGray6)))
                    }
                    
                    Spacer()
                    
                    Text("\(Int(percentageProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor.gradient)
                            .frame(width: geometry.size.width * percentageProgress, height: 8)
                    }
                }
                .frame(height: 8)
                
                // Budget text
                HStack {
	                    if isIncome {
	                        Text(remaining >= 0 ? "\(remaining.formatted(.currency(code: currencyCode))) to go" : "\(abs(remaining).formatted(.currency(code: currencyCode))) over goal")
	                            .font(.caption)
	                            .foregroundColor(progressColor)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                        
	                        Spacer()
	                        
	                        Text("\(activity.formatted(.currency(code: currencyCode))) received")
	                            .font(.caption)
	                            .foregroundColor(.secondary)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                    } else {
	                        Text(remaining >= 0 ? "\(remaining.formatted(.currency(code: currencyCode))) remaining" : "\(abs(remaining).formatted(.currency(code: currencyCode))) over budget")
	                            .font(.caption)
	                            .foregroundColor(progressColor)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                        
	                        Spacer()
	                        
	                        Text("\(activity.formatted(.currency(code: currencyCode))) of \(category.assigned.formatted(.currency(code: currencyCode)))")
	                            .font(.caption)
	                            .foregroundColor(.secondary)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ReviewView()
}

// MARK: - Month Swipe Navigation Modifier
struct MonthSwipeNavigationModifier: ViewModifier {
    @Binding var selectedDate: Date
    @State private var dragOffset: CGFloat = 0

    private let minimumDragDistance: CGFloat = 50

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 45)
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let calendar = Calendar.current

                        // Only trigger if horizontal swipe is dominant (more horizontal than vertical)
                        let horizontalDistance = abs(value.translation.width)
                        let verticalDistance = abs(value.translation.height)

                        guard horizontalDistance > verticalDistance else {
                            dragOffset = 0
                            return
                        }

                        // Swipe left (next month)
                        if value.translation.width < -minimumDragDistance {
                            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = nextMonth
                                }
                            }
                        }
                        // Swipe right (previous month)
                        else if value.translation.width > minimumDragDistance {
                            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = previousMonth
                                }
                            }
                        }

                        dragOffset = 0
                    }
            , including: .gesture)
    }
}

extension View {
    func monthSwipeNavigation(selectedDate: Binding<Date>) -> some View {
        self.modifier(MonthSwipeNavigationModifier(selectedDate: selectedDate))
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
