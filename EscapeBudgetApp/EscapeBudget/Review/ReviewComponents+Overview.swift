import SwiftUI
import SwiftData
import Charts



private struct MonthlyNetWorthPoint: Identifiable {
    let monthStart: Date
    let value: Decimal
    var id: Date { monthStart }
}

// MARK: - Overview View
	struct ReportsOverviewView: View {
	    @Environment(\.modelContext) private var modelContext
        @EnvironmentObject private var navigator: AppNavigator
	    @AppStorage("currencyCode") private var currencyCode = "USD"
	    @Query private var accounts: [Account]
	    @Query private var savingsGoals: [SavingsGoal]
	    @Query private var categoryGroups: [CategoryGroup]
	    @Query(sort: \MonthlyAccountTotal.monthStart, order: .reverse) private var monthlyAccountTotals: [MonthlyAccountTotal]

    @Binding var selectedDate: Date
    @State private var showingIncomeExpenseDetail: IncomeExpenseDetail?
    @State private var smallPurchaseReview: SmallPurchaseReviewSheetItem?
        @State private var showingUncategorizedFix = false
        @State private var categoryToFixBudget: Category?
        @State private var categoryToReview: Category?
        @State private var payeeToReview: PayeeReviewSheetItem?
        @State private var newRulePrefill: NewRulePrefillSheetItem?
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
	        let interval = PerformanceSignposts.begin("Review.recomputeAccountBalances")
	        defer { PerformanceSignposts.end(interval, "accounts=\(accounts.count) totals=\(monthlyAccountTotals.count)") }

	        // SwiftData can be fragile during early app lifecycle; bail out fast when there is no work.
	        guard !accounts.isEmpty || !monthlyAccountTotals.isEmpty else {
	            accountBalances = [:]
	            return
	        }

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
	        if !accounts.isEmpty && endDate < endExclusive.addingTimeInterval(-1) {
	            let fetchInterval = PerformanceSignposts.begin("Review.recomputeAccountBalances.fetchRemainder")
	            do {
	                let descriptor = FetchDescriptor<Transaction>(
	                    predicate: #Predicate<Transaction> { tx in
	                        tx.date > endDate && tx.date < endExclusive
	                    }
	                )
	                let txs = try modelContext.fetch(descriptor)
	                PerformanceSignposts.end(fetchInterval, "count=\(txs.count)")
	                for tx in txs {
	                    guard let accountID = tx.account?.persistentModelID else { continue }
	                    partialSameMonthAfterByAccountID[accountID, default: 0] += tx.amount
	                }
	            } catch {
	                PerformanceSignposts.end(fetchInterval, "error")
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

    private var velocityData: SpendingVelocityData {
        SpendingVelocityCalculator.compute(
            periodStart: dateRangeDates.0,
            periodEnd: dateRangeDates.1,
            totalSpent: periodExpenses,
            budgetAssigned: budgetAssigned
        )
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

	    private var insightRows: [OverviewInsightRowModel] {
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
            let predictiveInsightsForDisplay = predictiveInsights.filter { insight in
                // We already show a dedicated uncategorized row; avoid duplicating it via "unusual spending".
                if insight.type == .unusualSpending, uncategorizedCount > 0 {
                    return !(insight.relatedCategoryID == nil || insight.relatedCategoryName == "Uncategorized")
                }
                return true
            }

            func action(for insight: PredictiveInsightsEngine.Insight) -> OverviewInsightAction? {
                switch insight.type {
                case .budgetProjection:
                    guard let id = insight.relatedCategoryID else { return nil }
                    guard expenseCategories.contains(where: { $0.persistentModelID == id }) else { return nil }
                    return .fixBudgetCategory(id)
                case .unusualSpending:
                    if insight.relatedCategoryID == nil || insight.relatedCategoryName == "Uncategorized" {
                        return uncategorizedCount > 0 ? .openUncategorized : nil
                    }
                    guard let id = insight.relatedCategoryID else { return nil }
                    guard expenseCategories.contains(where: { $0.persistentModelID == id }) else { return nil }
                    return .showCategoryTransactions(id)
                case .recurringExpenseDetected:
                    guard let payee = insight.relatedPayee, !payee.isEmpty else { return nil }
                    return .reviewPayee(payee)
                case .spendingTrend, .savingsOpportunity:
                    return insight.actionable ? .showIncomeExpenseDetail(.expenses) : nil
                case .smallPurchases:
                    return insight.actionable ? .showSmallPurchases(20) : nil
                case .incomeVariation:
                    return insight.actionable ? .showIncomeExpenseDetail(.income) : nil
                case .upcomingBill:
                    guard let payee = insight.relatedPayee, !payee.isEmpty else { return nil }
                    return .reviewPayee(payee)
                }
            }

            func actionTitle(for action: OverviewInsightAction?, insightType: PredictiveInsightsEngine.Insight.InsightType? = nil) -> String? {
                switch action {
                case .openUncategorized, .fixBudgetCategory:
                    return "Fix"
                case .showCategoryTransactions, .reviewPayee:
                    // "Upcoming bill" is actionable but typically a review flow (not a fix).
                    if insightType == .upcomingBill { return "Review" }
                    return "Fix"
                case .showIncomeExpenseDetail, .showSmallPurchases, .openReview:
                    return "Review"
                case .importData:
                    return "Import"
                case .none:
                    return nil
                }
            }

            var rows: [OverviewInsightRowModel] = []

            if uncategorizedCount > 0 {
                rows.append(
                    OverviewInsightRowModel(
                        stableID: "uncategorized",
                        icon: "tag.slash.fill",
                        title: "Categorize uncategorized spending",
                        detail: "\(uncategorizedCount) transaction\(uncategorizedCount == 1 ? "" : "s") totaling \(uncategorizedAmount.formatted(.currency(code: currencyCode)))",
                        why: "Uncategorized transactions can hide trends and reduce report accuracy.",
                        severity: .warning,
                        actionTitle: actionTitle(for: .openUncategorized),
                        action: .openUncategorized
                    )
                )
            }

            let maxPredictiveInsights = uncategorizedCount > 0 ? 3 : 4
            rows.append(contentsOf: predictiveInsightsForDisplay.prefix(maxPredictiveInsights).map { insight in
                let insightAction = action(for: insight)
                return OverviewInsightRowModel(
                    stableID: OverviewInsightRowModel.stableID(for: insight),
                    icon: insight.severity.icon,
                    title: insight.title,
                    detail: insight.description,
                    why: insight.why,
                    severity: insight.severity,
                    actionTitle: actionTitle(for: insightAction, insightType: insight.type),
                    action: insightAction
                )
            })

            if rows.isEmpty {
                if let savingsRate {
                    if savingsRate < 0 {
                        rows.append(
                            OverviewInsightRowModel(
                                stableID: "over_income",
                                icon: PredictiveInsightsEngine.Insight.Severity.alert.icon,
                                title: "Spending over income",
                                detail: "\(periodExpenses.formatted(.currency(code: currencyCode))) expenses vs \(periodIncome.formatted(.currency(code: currencyCode))) income",
                                why: "This period’s expenses exceed your income.",
                                severity: .alert,
                                actionTitle: actionTitle(for: .openReview(.expenses)),
                                action: .openReview(.expenses)
                            )
                        )
                    } else if savingsRate < 0.10 {
                        rows.append(
                            OverviewInsightRowModel(
                                stableID: "save_more",
                                icon: PredictiveInsightsEngine.Insight.Severity.info.icon,
                                title: "Try saving a bit more",
                                detail: "A small cut can move your savings rate over 10%.",
                                why: "10% is a common baseline goal.",
                                severity: .info,
                                actionTitle: actionTitle(for: .openReview(.expenses)),
                                action: .openReview(.expenses)
                            )
                        )
                    } else {
                        rows.append(
                            OverviewInsightRowModel(
                                stableID: "savings_strong",
                                icon: PredictiveInsightsEngine.Insight.Severity.info.icon,
                                title: "Savings rate looks strong",
                                detail: "Keep the momentum going.",
                                why: nil,
                                severity: .info,
                                actionTitle: nil,
                                action: nil
                            )
                        )
                    }
                } else {
                    rows.append(
                        OverviewInsightRowModel(
                            stableID: "no_income",
                            icon: PredictiveInsightsEngine.Insight.Severity.info.icon,
                            title: "No income detected",
                            detail: "Import or add income to unlock more insights.",
                            why: nil,
                            severity: .info,
                            actionTitle: actionTitle(for: .importData),
                            action: .importData
                        )
                    )
                }

                if let topOver = overBudgetCategories.first {
                    rows.append(
                        OverviewInsightRowModel(
                            stableID: "over_budget_top",
                            icon: PredictiveInsightsEngine.Insight.Severity.warning.icon,
                            title: "\(topOver.category.name) is over budget",
                            detail: "Over by \(topOver.overBy.formatted(.currency(code: currencyCode))).",
                            why: "Based on spending in this period.",
                            severity: .warning,
                            actionTitle: actionTitle(for: .fixBudgetCategory(topOver.category.persistentModelID)),
                            action: .fixBudgetCategory(topOver.category.persistentModelID)
                        )
                    )
                } else if budgetAssigned > 0 {
                    rows.append(
                        OverviewInsightRowModel(
                            stableID: "budget_on_track",
                            icon: PredictiveInsightsEngine.Insight.Severity.info.icon,
                            title: "Budget looks on track",
                            detail: "No categories are currently over budget.",
                            why: nil,
                            severity: .info,
                            actionTitle: nil,
                            action: nil
                        )
                    )
                }
            }

            return Array(rows.prefix(4))
	    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.cardGap) {
                ScrollOffsetReader(coordinateSpace: "ReportsOverviewView.scroll", id: "ReportsOverviewView.scroll")
                topChromeView

                VStack(spacing: AppTheme.Spacing.cardGap) {
                    BudgetReviewSectionCard {
                        OverviewHealthCard(
                            score: healthScore,
                            insights: insightRows,
                            income: periodIncome,
                            expenses: periodExpenses,
                            currencyCode: currencyCode,
                            savingsRate: savingsRate,
                            onTapIncome: { showingIncomeExpenseDetail = .income },
                            onTapExpenses: { showingIncomeExpenseDetail = .expenses },
                            onTapInsightAction: handleInsightAction
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
                        OverviewSpendingVelocityCard(
                            velocityData: velocityData,
                            currencyCode: currencyCode
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
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.tight)
            }
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
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -AppTheme.Layout.scrollCompactThreshold
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
        .task(id: AccountBalanceTaskID(
            accountsCount: accounts.count,
            totalsCount: monthlyAccountTotals.count,
            dataChangeToken: DataChangeTracker.token,
            endDate: dateRangeDates.1
        )) {
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
        .sheet(item: $smallPurchaseReview) { item in
            let items = filteredTransactions
                .filter { $0.amount < 0 && abs($0.amount) < item.threshold }
                .sorted { $0.date > $1.date }
            IncomeExpenseDetailSheet(
                detail: .expenses,
                transactions: items,
                currencyCode: currencyCode,
                dateRange: dateRangeDates,
                accounts: accounts,
                categoryGroups: categoryGroups,
                titleOverride: "Small purchases"
            )
        }
        .sheet(isPresented: $showingUncategorizedFix) {
            UncategorizedTransactionsView(
                transactions: uncategorizedExpenses,
                currencyCode: currencyCode,
                categoryGroups: categoryGroups,
                onDismiss: {}
            )
        }
        .sheet(item: $payeeToReview) { item in
            PayeeTransactionsSheet(
                payee: item.payee,
                transactions: item.transactions,
                dateRange: item.dateRange,
                onCreateRule: {
                    newRulePrefill = NewRulePrefillSheetItem(
                        prefill: AutoRuleEditorView.Prefill(
                            name: "Rule for \(item.payee)",
                            matchPayeeCondition: .contains,
                            matchPayeeValue: item.payee.lowercased()
                        )
                    )
                }
            )
        }
        .sheet(item: $newRulePrefill) { item in
            NavigationStack {
                AutoRuleEditorView(rule: nil, prefill: item.prefill)
            }
        }
        .sheet(item: $categoryToFixBudget) { category in
            BudgetCategoryFixSheet(
                category: category,
                spent: spent(for: category),
                currencyCode: currencyCode,
                dateRange: dateRangeDates,
                transactions: filteredTransactions.filter { $0.category?.persistentModelID == category.persistentModelID }
            )
        }
        .sheet(item: $categoryToReview) { category in
            CategoryTransactionsSheet(
                category: category,
                transactions: filteredTransactions.filter { $0.category?.persistentModelID == category.persistentModelID },
                dateRange: dateRangeDates
            )
        }
    }

    private var topChromeView: some View {
        DateRangeFilterHeader(
            filterMode: $filterMode,
            date: $selectedDate,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate,
            isCompact: isRangeHeaderCompact
        )
        .topMenuBarStyle(isCompact: isRangeHeaderCompact)
    }

    private func handleInsightAction(_ action: OverviewInsightAction) {
        switch action {
        case .openUncategorized:
            showingUncategorizedFix = true
        case .fixBudgetCategory(let categoryID):
            categoryToFixBudget = expenseCategories.first { $0.persistentModelID == categoryID }
        case .showCategoryTransactions(let categoryID):
            categoryToReview = expenseCategories.first { $0.persistentModelID == categoryID }
        case .reviewPayee(let payee):
            let key = PayeeNormalizer.normalizeForComparison(payee)
            let calendar = Calendar.current
            let end = dateRangeDates.1
            let start = calendar.date(byAdding: .month, value: -12, to: end) ?? dateRangeDates.0
            let transactions = fetchPayeeTransactions(key: key, start: start, end: end)
            payeeToReview = PayeeReviewSheetItem(payee: payee, key: key, transactions: transactions, dateRange: (start, end))
        case .showIncomeExpenseDetail(let detail):
            showingIncomeExpenseDetail = detail
        case .showSmallPurchases(let threshold):
            smallPurchaseReview = SmallPurchaseReviewSheetItem(threshold: threshold)
        case .openReview(let section):
            navigator.openReview(section: section, date: selectedDate, filterMode: filterMode, customStartDate: customStartDate, customEndDate: customEndDate)
        case .importData:
            navigator.importData()
        }
    }

    private func fetchPayeeTransactions(key: String, start: Date, end: Date) -> [Transaction] {
        let standard = TransactionKind.standard.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.kindRawValue == standard &&
                tx.date >= start &&
                tx.date <= end
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )

        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        return fetched.filter { tx in
            tx.account?.isTrackingOnly != true &&
            PayeeNormalizer.normalizeForComparison(tx.payee) == key
        }
    }
}

private struct PayeeReviewSheetItem: Identifiable {
    let id = UUID()
    let payee: String
    let key: String
    let transactions: [Transaction]
    let dateRange: (start: Date, end: Date)

    init(payee: String, key: String? = nil, transactions: [Transaction], dateRange: (start: Date, end: Date)) {
        self.payee = payee
        self.key = key ?? PayeeNormalizer.normalizeForComparison(payee)
        self.transactions = transactions
        self.dateRange = dateRange
    }
}

private struct SmallPurchaseReviewSheetItem: Identifiable {
    let id = UUID()
    let threshold: Decimal
}

private struct NewRulePrefillSheetItem: Identifiable {
    let id = UUID()
    let prefill: AutoRuleEditorView.Prefill
}

private struct ReportsRangeTransactionsQuery: View {
    @Query private var transactions: [Transaction]
    private let onUpdate: ([Transaction]) -> Void
    private let start: Date
    private let end: Date

    init(start: Date, end: Date, onUpdate: @escaping ([Transaction]) -> Void) {
        self.start = start
        self.end = end
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
        Color.clear
            .task(id: ReportsRangeTransactionsTaskID(
                transactionsCount: transactions.count,
                dataChangeToken: DataChangeTracker.token,
                start: start,
                end: end
            )) {
                onUpdate(transactions)
            }
    }
}

private struct AccountBalanceTaskID: Equatable {
    var accountsCount: Int
    var totalsCount: Int
    var dataChangeToken: Int
    var endDate: Date
}

private struct ReportsRangeTransactionsTaskID: Equatable {
    var transactionsCount: Int
    var dataChangeToken: Int
    var start: Date
    var end: Date
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
    let insights: [OverviewInsightRowModel]
    let income: Decimal
    let expenses: Decimal
    let currencyCode: String
    let savingsRate: Double?
    let onTapIncome: () -> Void
    let onTapExpenses: () -> Void
    let onTapInsightAction: (OverviewInsightAction) -> Void
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .top, spacing: AppTheme.Spacing.tight) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Financial Health")
	                        .appSectionTitleText()

	                    Text(scoreLabel)
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                }

                Spacer()

                BudgetReviewRingProgress(progress: Double(score) / 100.0, color: scoreColor)
            }

            HStack(spacing: AppTheme.Spacing.small) {
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
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
	                    Text("Insights")
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)

                    ForEach(insights) { insight in
                        OverviewInsightRow(model: insight) { action in
                            onTapInsightAction(action)
                        }
                    }
                }
            }
        }
    }
}

private enum OverviewInsightAction: Hashable {
    case openUncategorized
    case fixBudgetCategory(PersistentIdentifier)
    case showCategoryTransactions(PersistentIdentifier)
    case reviewPayee(String)
    case showIncomeExpenseDetail(IncomeExpenseDetail)
    case showSmallPurchases(Decimal)
    case openReview(AppNavigator.ReviewSection)
    case importData
}

private struct OverviewInsightRowModel: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let why: String?
    let severity: PredictiveInsightsEngine.Insight.Severity
    let actionTitle: String?
    let action: OverviewInsightAction?

    init(
        stableID: String,
        icon: String,
        title: String,
        detail: String,
        why: String?,
        severity: PredictiveInsightsEngine.Insight.Severity,
        actionTitle: String?,
        action: OverviewInsightAction?
    ) {
        self.id = stableID
        self.icon = icon
        self.title = title
        self.detail = detail
        self.why = why
        self.severity = severity
        self.actionTitle = actionTitle
        self.action = action
    }

    static func stableID(for insight: PredictiveInsightsEngine.Insight) -> String {
        var components: [String] = []
        components.append(String(describing: insight.type))

        if let relatedCategoryName = insight.relatedCategoryName, !relatedCategoryName.isEmpty {
            components.append("cat_\(relatedCategoryName)")
        } else if let relatedCategoryID = insight.relatedCategoryID {
            components.append("catid_\(String(describing: relatedCategoryID))")
        }

        if let relatedPayee = insight.relatedPayee, !relatedPayee.isEmpty {
            components.append("payee_\(PayeeNormalizer.normalizeForComparison(relatedPayee))")
        }

        return sanitizeIdentifierComponent(components.joined(separator: "__"))
    }

    private static func sanitizeIdentifierComponent(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
        return replaced.isEmpty ? "unknown" : replaced
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
    let titleOverride: String?

    init(
        detail: IncomeExpenseDetail,
        transactions: [Transaction],
        currencyCode: String,
        dateRange: (start: Date, end: Date),
        accounts: [Account],
        categoryGroups: [CategoryGroup],
        titleOverride: String? = nil
    ) {
        self.detail = detail
        self.transactions = transactions
        self.currencyCode = currencyCode
        self.dateRange = dateRange
        self.accounts = accounts
        self.categoryGroups = categoryGroups
        self.titleOverride = titleOverride
    }

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
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text(titleOverride ?? detail.title)
                                .appSectionTitleText()

	                            Text(dateRangeTitle)
	                                .appSecondaryBodyText()
	                                .foregroundStyle(.secondary)
	                        }

                        Spacer()

	                        Text(total, format: .currency(code: currencyCode))
	                            .appSectionTitleText()
	                            .fontWeight(.semibold)
	                            .foregroundStyle(detail == .income ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, AppTheme.Spacing.micro)
                }

                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        hasActiveFilters ? "No Matching Transactions" : "No \(titleOverride ?? detail.title)",
                        systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray",
                        description: Text(hasActiveFilters ? "Try adjusting your filters." : "No \((titleOverride ?? detail.title).lowercased()) transactions found for this period.")
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

struct OverviewTransactionRow: View {
    let transaction: Transaction
    let currencyCode: String
    let emphasizeOutflow: Bool
    @Environment(\.appColorMode) private var appColorMode

    private var amountColor: Color {
        if transaction.amount >= 0 { return AppColors.success(for: appColorMode) }
        return emphasizeOutflow ? AppColors.danger(for: appColorMode) : .primary
    }

    var body: some View {
	        HStack(spacing: AppTheme.Spacing.tight) {
	            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                Text(transaction.payee)
	                    .appSecondaryBodyText()
	                    .fontWeight(.medium)
	                    .foregroundStyle(.primary)
	                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.compact) {
                    Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    if transaction.isTransfer {
                        Text("Transfer")
                            .font(.caption2)
                            .padding(.horizontal, AppTheme.Spacing.xSmall)
                            .padding(.vertical, AppTheme.Spacing.hairline)
                            .background(Capsule().fill(AppColors.tint(for: appColorMode).opacity(0.1)))
                            .foregroundStyle(AppColors.tint(for: appColorMode))
                            .lineLimit(1)
                    } else if let category = transaction.category {
                        Text(category.name)
                            .font(.caption2)
                            .padding(.horizontal, AppTheme.Spacing.xSmall)
                            .padding(.vertical, AppTheme.Spacing.hairline)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Uncategorized")
                            .font(.caption2)
                            .padding(.horizontal, AppTheme.Spacing.xSmall)
                            .padding(.vertical, AppTheme.Spacing.hairline)
                            .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.12)))
                            .foregroundStyle(AppColors.warning(for: appColorMode))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

	            Text(transaction.amount, format: .currency(code: currencyCode))
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)
	                .foregroundStyle(amountColor)
	                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, AppTheme.Spacing.micro)
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
        return formatter.currencySymbol ?? currencyCode
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .firstTextBaseline) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Net Worth")
	                        .appSectionTitleText()
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
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small)
                ],
                spacing: AppTheme.Spacing.small
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

                                VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                                    Text(selectedPoint.monthStart, format: .dateTime.month(.abbreviated).year())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedPoint.value, format: .currency(code: currencyCode))
                                        .appCaptionText()
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, AppTheme.Spacing.compact)
                                .padding(.vertical, AppTheme.Spacing.xSmall)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                                        .fill(Color(.systemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
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
                .padding(.top, AppTheme.Spacing.hairline)
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            Text("Cash Flow")
	                .appSectionTitleText()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.small), GridItem(.flexible(), spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
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
                .appCaptionText()
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .firstTextBaseline) {
	                Text("Budget Health")
	                    .appSectionTitleText()

                Spacer()

                if assigned > 0 {
                    Text("\(Int((utilization ?? 0) * 100))% used")
                        .appCaptionText()
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
                .padding(.vertical, AppTheme.Spacing.xSmall)
            } else {
                OverviewInlineMeter(
                    title: "Spent vs Assigned",
                    valueText: "\(spent.formatted(.currency(code: currencyCode))) of \(assigned.formatted(.currency(code: currencyCode)))",
                    progress: utilization ?? 0,
                    tint: utilizationColor
                )

                LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.small), GridItem(.flexible(), spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
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
	                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
	                        Text("Over Budget")
	                            .appSecondaryBodyText()
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
                            .appCaptionText()
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .firstTextBaseline) {
	                Text("Top Spending")
	                    .appSectionTitleText()

                Spacer()

	                Text(totalSpending, format: .currency(code: currencyCode))
	                    .appSecondaryBodyText()
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
                .padding(.vertical, AppTheme.Spacing.xSmall)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(items, id: \.name) { item in
                        let pct = totalSpending > 0 ? Double(truncating: (item.total / totalSpending) as NSNumber) : 0
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
	                            HStack {
	                                Text(item.name)
	                                    .appSecondaryBodyText()
	                                    .lineLimit(1)
	                                Spacer()
	                                Text(item.total, format: .currency(code: currencyCode))
	                                    .appSecondaryBodyText()
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            Text("Categorization")
	                .appSectionTitleText()

            OverviewInlineMeter(
                title: "Categorized Spend",
                valueText: "\(Int(pctCategorized * 100))% categorized",
                progress: pctCategorized,
                tint: uncategorizedCount > 0 ? AppColors.warning(for: appColorMode) : AppColors.success(for: appColorMode)
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.small), GridItem(.flexible(), spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
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
                .appCaptionText()
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .firstTextBaseline) {
	                Text("Savings Goals")
	                    .appSectionTitleText()

                Spacer()

                if let totalProgress {
                    Text("\(Int(totalProgress * 100))% overall")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(spacing: AppTheme.Spacing.tight) {
                ForEach(goals, id: \.persistentModelID) { goal in
                    let progress = min(1, max(0, goal.progressPercentage / 100))
                    let fallback = AppColors.tint(for: appColorMode)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                        HStack {
                            HStack(spacing: AppTheme.Spacing.compact) {
	                                Circle()
	                                    .fill(Color(hex: goal.colorHex) ?? fallback)
	                                    .frame(width: 10, height: 10)
	                                Text(goal.name)
	                                    .appSecondaryBodyText()
	                                    .fontWeight(.semibold)
	                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("\(goal.currentAmount.formatted(.currency(code: currencyCode))) / \(goal.targetAmount.formatted(.currency(code: currencyCode)))")
                                .appCaptionText()
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            Text("Highlights")
	                .appSectionTitleText()

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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
	            Text("Deep Dive")
	                .appSectionTitleText()

            VStack(spacing: AppTheme.Spacing.small) {
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
            customEndDate: $customEndDate,
            topChrome: { AnyView(topChromeView) }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -AppTheme.Layout.scrollCompactThreshold
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

    private var topChromeView: some View {
        DateRangeFilterHeader(
            filterMode: $filterMode,
            date: $selectedDate,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate,
            isCompact: isHeaderCompact
        )
        .topMenuBarStyle(isCompact: isHeaderCompact)
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
            customEndDate: $customEndDate,
            topChrome: { AnyView(topChromeView) }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -AppTheme.Layout.scrollCompactThreshold
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

    private var topChromeView: some View {
        DateRangeFilterHeader(
            filterMode: $filterMode,
            date: $selectedDate,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate,
            isCompact: isHeaderCompact
        )
        .topMenuBarStyle(isCompact: isHeaderCompact)
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
            customEndDate: $customEndDate,
            topChrome: { AnyView(topChromeView) }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -AppTheme.Layout.scrollCompactThreshold
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

    private var topChromeView: some View {
        DateRangeFilterHeader(
            filterMode: $filterMode,
            date: $selectedDate,
            customStartDate: $customStartDate,
            customEndDate: $customEndDate,
            isCompact: isHeaderCompact
        )
        .topMenuBarStyle(isCompact: isHeaderCompact)
    }
}

struct OverviewMetricTile: View {
    let title: String
    let valueText: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Text(valueText)
                .font(AppTheme.Typography.secondaryBody)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct OverviewValueTile: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)

            Text(value, format: .currency(code: currencyCode))
                .font(AppTheme.Typography.secondaryBody)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct OverviewInlineMeter: View {
    let title: String
    let valueText: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            HStack {
                Text(title)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .appCaptionText()
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
    let model: OverviewInsightRowModel
    let onAction: (OverviewInsightAction) -> Void
    @Environment(\.appColorMode) private var appColorMode

	    var body: some View {
	        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                Image(systemName: model.icon)
                    .foregroundStyle(iconTint)
                    .appCaptionText()
                    .padding(.top, AppTheme.Spacing.pixel)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                    Text(model.title)
                        .appSecondaryBodyText()
                        .foregroundStyle(.primary)

                    Text(model.detail)
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    if let why = model.why, !why.isEmpty {
                        Text(why)
                            .appCaptionText()
                            .foregroundStyle(.tertiary)
                    }
                }

            Spacer(minLength: 0)

                if let action = model.action, let title = model.actionTitle {
                    Button(title) {
                        onAction(action)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("overviewInsight.action.\(model.id)")
                }
        }
        .padding(AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overviewInsight.row.\(model.id)")
    }

    private var iconTint: Color {
        switch model.severity {
        case .info:
            return AppColors.tint(for: appColorMode)
        case .warning:
            return AppColors.warning(for: appColorMode)
        case .alert:
            return AppColors.danger(for: appColorMode)
        }
    }
}

struct OverviewStatChip: View {
    let icon: String
    let label: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

	    var body: some View {
	        HStack(spacing: AppTheme.Spacing.small) {
	            Image(systemName: icon)
	                .foregroundStyle(tint)
	                .font(AppTheme.Typography.sectionTitle)

	            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                Text(label)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
	                Text(value, format: .currency(code: currencyCode))
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
	                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.small)
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

struct OverviewInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = .secondary

	    var body: some View {
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            HStack(spacing: AppTheme.Spacing.tight) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 22)

	                Text(title)
	                    .appSecondaryBodyText()
	                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

	                Text(value)
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
	                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let subtitle {
                Text(subtitle)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, AppTheme.Spacing.indentMedium)
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct OverviewLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.appColorMode) private var appColorMode

	    var body: some View {
            HStack(spacing: AppTheme.Spacing.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                    .fill(AppColors.tint(for: appColorMode).opacity(0.12))
                Image(systemName: icon)
                    .foregroundStyle(AppColors.tint(for: appColorMode))
                    .font(AppTheme.Typography.sectionTitle)
            }
            .frame(width: 40, height: 40)

	            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
	                Text(title)
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
	                    .foregroundStyle(.primary)
                Text(subtitle)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .appCaptionText()
        }
        .padding(AppTheme.Spacing.small)
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
