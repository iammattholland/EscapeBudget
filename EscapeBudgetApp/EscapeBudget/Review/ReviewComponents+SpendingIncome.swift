import SwiftUI
import SwiftData
import Charts

struct ReportsSpendingView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]

    @Binding var selectedDate: Date
    @Binding var filterMode: DateRangeFilterHeader.FilterMode
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var drilldown: ReviewTransactionDrilldown? = nil
    @State private var transactionToEdit: Transaction? = nil
    @State private var showingUncategorizedFix = false
    @State private var rangedTransactions: [Transaction] = []
    @State private var metrics: SpendingMetrics = .empty

    private var filteredTransactions: [Transaction] {
        metrics.filteredTransactions
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

    private var spendingMetricsTaskID: SpendingMetricsTaskID {
        SpendingMetricsTaskID(
            transactionsCount: rangedTransactions.count,
            dataChangeToken: DataChangeTracker.token,
            start: dateRangeDates.0,
            end: dateRangeDates.1
        )
    }
    
    private var spendingByCategory: [(String, Decimal)] {
        metrics.spendingByCategory
    }
    
    private var spendingByMerchant: [(String, Decimal)] {
        metrics.spendingByMerchant
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
        metrics.largestExpense
    }
    
    private var uncategorizedAmount: Decimal {
        metrics.uncategorizedAmount
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
        metrics.totalSpending
    }

    private var spendingCallouts: [ReviewCalloutBar.Item] {
        var items: [ReviewCalloutBar.Item] = []
        items.reserveCapacity(4)

        items.append(
            ReviewCalloutBar.Item(
                id: "view_all_expenses",
                systemImage: "list.bullet",
                title: "View all expenses",
                value: "\(filteredTransactions.count) tx",
                tint: AppColors.danger(for: appColorMode),
                action: {
                    drilldown = ReviewTransactionDrilldown(
                        title: "All Expenses",
                        subtitle: ReviewTrendSeries.subtitleText(for: dateRangeDates),
                        transactions: filteredTransactions.sorted { $0.date > $1.date },
                        currencyCode: currencyCode,
                        emphasizeOutflow: true
                    )
                }
            )
        )

        if uncategorizedAmount > 0 {
            let uncategorizedCount = filteredTransactions.filter { $0.category == nil }.count
            items.append(
                ReviewCalloutBar.Item(
                    id: "uncategorized_expenses",
                    systemImage: "tag.slash",
                    title: "Uncategorized",
                    value: "\(uncategorizedAmount.formatted(.currency(code: currencyCode))) • \(uncategorizedCount) tx",
                    tint: AppColors.warning(for: appColorMode),
                    action: { showingUncategorizedFix = true }
                )
            )
        }

        if let largestExpense {
            items.append(
                ReviewCalloutBar.Item(
                    id: "largest_expense",
                    systemImage: "arrow.up.right.circle.fill",
                    title: "Largest expense",
                    value: abs(largestExpense.amount).formatted(.currency(code: currencyCode)),
                    tint: AppColors.danger(for: appColorMode),
                    action: { transactionToEdit = largestExpense }
                )
            )
        }

        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.cardGap) {
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
                    ReviewCalloutBar(title: "Quick Actions", items: spendingCallouts, isVertical: true)
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

                // Insights live on Home; Review keeps action-oriented callouts.
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.tight)
        }
        .background(SpendingTransactionsQuery(start: dateRangeDates.0, end: dateRangeDates.1) { fetched in
            rangedTransactions = fetched
        })
        .task(id: spendingMetricsTaskID) {
            recomputeMetrics()
        }
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(name: "ReportsSpendingView.scroll")
        .sheet(item: $drilldown) { drilldown in
            ReviewTransactionsSheet(drilldown: drilldown)
        }
        .sheet(item: $transactionToEdit) { transaction in
            TransactionFormView(transaction: transaction)
        }
        .sheet(isPresented: $showingUncategorizedFix) {
            let uncategorized = filteredTransactions
                .filter { $0.category == nil }
                .sorted { $0.date > $1.date }
            UncategorizedTransactionsView(
                transactions: uncategorized,
                currencyCode: currencyCode,
                categoryGroups: categoryGroups,
                onDismiss: { }
            )
        }
    }

    private func recomputeMetrics() {
        let filtered = rangedTransactions.filter { $0.account?.isTrackingOnly != true }
        var categoryTotals: [String: Decimal] = [:]
        var merchantTotals: [String: Decimal] = [:]
        var total: Decimal = 0
        var uncategorized: Decimal = 0
        var largest: Transaction?

        for transaction in filtered {
            let amount = abs(transaction.amount)
            total += amount

            let categoryName = transaction.category?.name ?? "Uncategorized"
            categoryTotals[categoryName, default: 0] += amount

            let merchant = transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            let merchantName = merchant.isEmpty ? "Unknown" : merchant
            merchantTotals[merchantName, default: 0] += amount

            if transaction.category == nil {
                uncategorized += amount
            }

            if let currentLargest = largest {
                if transaction.amount < currentLargest.amount {
                    largest = transaction
                }
            } else {
                largest = transaction
            }
        }

        metrics = SpendingMetrics(
            filteredTransactions: filtered,
            spendingByCategory: categoryTotals.sorted { $0.value > $1.value },
            spendingByMerchant: merchantTotals.sorted { $0.value > $1.value },
            totalSpending: total,
            uncategorizedAmount: uncategorized,
            largestExpense: largest
        )
    }
}

private struct SpendingMetrics {
    var filteredTransactions: [Transaction] = []
    var spendingByCategory: [(String, Decimal)] = []
    var spendingByMerchant: [(String, Decimal)] = []
    var totalSpending: Decimal = 0
    var uncategorizedAmount: Decimal = 0
    var largestExpense: Transaction? = nil

    static let empty = SpendingMetrics()
}

private struct SpendingMetricsTaskID: Equatable {
    var transactionsCount: Int
    var dataChangeToken: Int
    var start: Date
    var end: Date
}

private struct SpendingQueryTaskID: Equatable {
    var transactionsCount: Int
    var dataChangeToken: Int
    var start: Date
    var end: Date
}

private struct SpendingTransactionsQuery: View {
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
                tx.kindRawValue == kind &&
                tx.amount < 0
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    var body: some View {
        Color.clear
            .task(id: SpendingQueryTaskID(
                transactionsCount: transactions.count,
                dataChangeToken: DataChangeTracker.token,
                start: start,
                end: end
            )) {
                onUpdate(transactions)
            }
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
    @State private var transactionToEdit: Transaction? = nil

    // Use @Query to fetch all standard transactions, then filter in computed property
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "Standard"
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

    private var incomeCallouts: [ReviewCalloutBar.Item] {
        var items: [ReviewCalloutBar.Item] = []
        items.reserveCapacity(4)

        items.append(
            ReviewCalloutBar.Item(
                id: "view_all_income",
                systemImage: "list.bullet",
                title: "View all income",
                value: "\(filteredTransactions.count) tx",
                tint: AppColors.success(for: appColorMode),
                action: {
                    drilldown = ReviewTransactionDrilldown(
                        title: "All Income",
                        subtitle: ReviewTrendSeries.subtitleText(for: dateRangeDates),
                        transactions: filteredTransactions.sorted { $0.date > $1.date },
                        currencyCode: currencyCode,
                        emphasizeOutflow: false
                    )
                }
            )
        )

        if let (payer, amount) = incomeByPayer.first {
            items.append(
                ReviewCalloutBar.Item(
                    id: "top_payer",
                    systemImage: "person.crop.circle.fill",
                    title: "Top payer",
                    value: "\(payer) • \(amount.formatted(.currency(code: currencyCode)))",
                    tint: AppColors.tint(for: appColorMode),
                    action: {
                        let matching = filteredTransactions
                            .filter { $0.payee.trimmingCharacters(in: .whitespacesAndNewlines) == payer }
                            .sorted { $0.date > $1.date }
                        drilldown = ReviewTransactionDrilldown(
                            title: payer,
                            subtitle: "Income",
                            transactions: matching,
                            currencyCode: currencyCode,
                            emphasizeOutflow: false
                        )
                    }
                )
            )
        }

        if let largestIncome {
            items.append(
                ReviewCalloutBar.Item(
                    id: "largest_income",
                    systemImage: "arrow.down.left.circle.fill",
                    title: "Largest income",
                    value: largestIncome.amount.formatted(.currency(code: currencyCode)),
                    tint: AppColors.success(for: appColorMode),
                    action: { transactionToEdit = largestIncome }
                )
            )
        }

        return items
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
            VStack(spacing: AppTheme.Spacing.cardGap) {
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
                    ReviewCalloutBar(title: "Quick Actions", items: incomeCallouts, isVertical: true)
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

                // Insights live on Home; Review keeps action-oriented callouts.
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.tight)
        }
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(name: "ReportsIncomeView.scroll")
        .sheet(item: $drilldown) { drilldown in
            ReviewTransactionsSheet(drilldown: drilldown)
        }
        .sheet(item: $transactionToEdit) { transaction in
            TransactionFormView(transaction: transaction)
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
    @State private var selectedTransaction: Transaction?

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
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                            Text(drilldown.title)
	                                .appSectionTitleText()
	                            Text(drilldown.subtitle)
	                                .appSecondaryBodyText()
	                                .foregroundStyle(.secondary)
	                        }

                        Spacer()

	                        Text(total, format: .currency(code: drilldown.currencyCode))
	                            .appSectionTitleText()
	                            .fontWeight(.semibold)
	                            .foregroundStyle(drilldown.emphasizeOutflow ? AppColors.danger(for: appColorMode) : AppColors.success(for: appColorMode))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, AppTheme.Spacing.micro)
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
                            Button {
                                selectedTransaction = transaction
                            } label: {
                                OverviewTransactionRow(
                                    transaction: transaction,
                                    currencyCode: drilldown.currencyCode,
                                    emphasizeOutflow: drilldown.emphasizeOutflow
                                )
                            }
                            .buttonStyle(.plain)
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
            .sheet(item: $selectedTransaction) { transaction in
                TransactionFormView(transaction: transaction)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
	            HStack(alignment: .firstTextBaseline) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text(title)
	                        .appSectionTitleText()
                    Text(subtitle)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if maxValue > 0 {
                    Text("Peak \(maxValue.formatted(.currency(code: currencyCode)))")
                        .appCaptionText()
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
                .padding(.vertical, AppTheme.Spacing.xSmall)
            } else {
	                Chart(series.buckets) { bucket in
	                    BarMark(
	                        x: .value("Date", bucket.start),
	                        y: .value("Total", NSDecimalNumber(decimal: bucket.total).doubleValue)
	                    )
	                    .foregroundStyle(tint.gradient)
	                    .cornerRadius(AppTheme.Radius.tag)
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
                .padding(.vertical, AppTheme.Spacing.micro)
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
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
	            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                Text(title)
	                    .appSectionTitleText()
                Text(subtitle)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty || total <= 0 {
                ContentUnavailableView(
                    "Not enough data",
                    systemImage: "tray",
                    description: Text("Add transactions to populate this breakdown.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xSmall)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(items, id: \.0) { item in
                        let pct = total > 0 ? Double(truncating: (item.1 / total) as NSNumber) : 0
                        Button {
                            onSelect(item.0)
                        } label: {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
	                                HStack {
	                                    Text(item.0)
	                                        .appSecondaryBodyText()
	                                        .foregroundStyle(.primary)
	                                        .lineLimit(1)

                                    Spacer()

	                                    Text(item.1, format: .currency(code: currencyCode))
	                                        .appSecondaryBodyText()
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
	            HStack(alignment: .firstTextBaseline) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Spending")
	                        .appSectionTitleText()
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.danger(for: appColorMode))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Text("\(transactionCount) tx")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.small), GridItem(.flexible(), spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Income")
	                        .appSectionTitleText()
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.success(for: appColorMode))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Text("\(transactionCount) tx")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.small), GridItem(.flexible(), spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
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

struct ReviewStoryCard: View {
    let title: String
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.compact) {
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
