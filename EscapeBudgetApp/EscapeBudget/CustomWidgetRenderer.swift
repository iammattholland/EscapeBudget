import SwiftUI
import SwiftData
import Charts

struct CustomWidgetRenderer: View {
    let widget: CustomDashboardWidget
    @Environment(\.modelContext) private var modelContext
    @Query private var categoryGroups: [CategoryGroup]
    @Query private var accounts: [Account]
    @Query(sort: \RecurringPurchase.nextDate) private var recurringPurchases: [RecurringPurchase]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    @State private var transactionsCache: [Transaction] = []
    @State private var filteredTransactionsCache: [Transaction] = []
    
    private var filteredTransactions: [Transaction] {
        filteredTransactionsCache
    }

    private var filteredTransactionsKey: String {
        let (start, end) = widget.dateRange.dateRange()
        return "\(widget.id.uuidString)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(DataChangeTracker.token)"
    }
    
    var body: some View {
        Group {
            if widget.widgetType == .table {
                renderTable()
            } else {
                renderChart()
            }
        }
        .task(id: filteredTransactionsKey) {
            let (start, end) = widget.dateRange.dateRange()
            let now = Date()
            let calendar = Calendar.current
            let thisYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYearStart) ?? thisYearStart
            let fourQuartersStart = calendar.date(byAdding: .month, value: -12, to: now) ?? now

            let requiredStart = min(start, lastYearStart, fourQuartersStart)
            let requiredEnd = max(end, now)

            let interval = PerformanceSignposts.begin("Widget.fetchTransactions")
            defer { PerformanceSignposts.end(interval, "type=\(widget.dataType.rawValue) range=\(requiredStart.timeIntervalSince1970)-\(requiredEnd.timeIntervalSince1970)") }

            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.date >= requiredStart && tx.date <= requiredEnd
                },
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )

            let fetched = (try? modelContext.fetch(descriptor)) ?? []
            transactionsCache = fetched
            filteredTransactionsCache = fetched.filter { $0.date >= start && $0.date <= end }
        }
    }
    
    // MARK: - Chart Rendering
    
    @ViewBuilder
    private func renderChart() -> some View {
        switch widget.dataType {
        // Basic Views
        case .spendingByCategory:
            let data = buildCategorySpending()
            renderCategoryChart(data: data, isEmpty: data.isEmpty, emptyMessage: "No spending data")

        case .incomeBySource:
            let data = buildIncomeSources()
            if data.isEmpty {
                WidgetEmptyStateView(message: "No income data")
            } else {
                Chart(data, id: \.name) { item in
                    if widget.chartType == .pie {
                        SectorMark(angle: .value("Amount", item.amount))
                            .foregroundStyle(by: .value("Source", item.name))
                    } else {
                        BarMark(x: .value("Source", item.name), y: .value("Amount", item.amount))
                            .foregroundStyle(AppColors.success(for: appColorMode).gradient)
                    }
                }
            }

        case .transactions:
            WidgetEmptyStateView(message: "Charts not available for raw transactions")

        // Trends & Patterns
        case .spendingTrend:
            renderTrendChart(data: buildSpendingTrend(), color: AppColors.danger(for: appColorMode), emptyMessage: "No spending data")

        case .incomeTrend:
            renderTrendChart(data: buildIncomeTrend(), color: AppColors.success(for: appColorMode), emptyMessage: "No income data")

        case .categoryTrend:
            renderTrendChart(data: buildCategoryTrendData(), color: AppColors.tint(for: appColorMode), emptyMessage: "No category data")

        case .dailySpendingPattern:
            renderPatternChart(data: buildDailyPattern(), emptyMessage: "No spending data")

        case .weeklySpendingPattern:
            renderTrendChart(data: buildWeeklyPattern(), color: AppColors.danger(for: appColorMode), emptyMessage: "No spending data")

        case .monthlySpendingPattern:
            renderTrendChart(data: buildMonthlyPattern(), color: AppColors.danger(for: appColorMode), emptyMessage: "No spending data")

        // Comparisons
        case .incomeVsExpenses:
            renderIncomeVsExpensesChart()

        case .monthOverMonth:
            renderComparisonChart(data: buildMonthOverMonth(), emptyMessage: "Not enough data")

        case .yearOverYear:
            renderComparisonChart(data: buildYearOverYear(), emptyMessage: "Not enough data")

        case .periodComparison:
            renderComparisonChart(data: buildPeriodComparison(), emptyMessage: "Not enough data")

        // Financial Health
        case .netWorthOverTime:
            renderTrendChart(data: buildNetWorthTrend(), color: AppColors.tint(for: appColorMode), emptyMessage: "No account data")

        case .savingsRate:
            renderSavingsRateChart()

        case .budgetPerformance:
            renderBudgetPerformanceChart()

        case .cashFlow:
            renderCashFlowChart()

        // Top Lists
        case .topExpenses:
            renderTopListChart(data: buildTopExpenses(), emptyMessage: "No expenses")

        case .topCategories:
            let data = buildTopCategories()
            renderCategoryChart(data: data, isEmpty: data.isEmpty, emptyMessage: "No categories")

        case .topMerchants:
            renderTopListChart(data: buildTopMerchants(), emptyMessage: "No merchants")

        case .recurringExpenses:
            renderTopListChart(data: buildRecurringExpenses(), emptyMessage: "No recurring expenses detected")

        // Analytics
        case .averageTransaction:
            renderAverageTransactionChart()

        case .transactionFrequency:
            renderFrequencyChart()

        case .categoryDistribution:
            let data = buildCategorySpending()
            if data.isEmpty {
                WidgetEmptyStateView(message: "No spending data")
            } else {
                Chart(data, id: \.name) { item in
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.6), angularInset: 2)
                        .foregroundStyle(by: .value("Category", item.name))
                }
            }

        case .accountBalances:
            renderAccountBalancesChart()

        case .upcomingBills:
            renderUpcomingBillsView()
        }
    }

    // MARK: - Chart Renderers

    @ViewBuilder
    private func renderCategoryChart(data: [ChartData], isEmpty: Bool, emptyMessage: String) -> some View {
        if isEmpty {
            WidgetEmptyStateView(message: emptyMessage)
        } else {
            Chart(data, id: \.name) { item in
                if widget.chartType == .pie {
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.6), angularInset: 2)
                        .foregroundStyle(by: .value("Category", item.name))
                } else if widget.chartType == .bar {
                    BarMark(x: .value("Category", item.name), y: .value("Amount", item.amount))
                        .foregroundStyle(by: .value("Category", item.name))
                } else {
                    LineMark(x: .value("Category", item.name), y: .value("Amount", item.amount))
                }
            }
        }
    }

    @ViewBuilder
    private func renderTrendChart(data: [TimeSeriesData], color: Color, emptyMessage: String) -> some View {
        if data.isEmpty {
            WidgetEmptyStateView(message: emptyMessage)
        } else {
            Chart(data) { item in
                if widget.chartType == .bar {
                    BarMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                        .foregroundStyle(color.gradient)
                } else {
                    LineMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                        .foregroundStyle(color)
                        .symbol(.circle)
                    AreaMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                        .foregroundStyle(color.opacity(0.1))
                }
            }
        }
    }

    @ViewBuilder
    private func renderPatternChart(data: [ChartData], emptyMessage: String) -> some View {
        if data.isEmpty {
            WidgetEmptyStateView(message: emptyMessage)
        } else {
            Chart(data, id: \.name) { item in
                BarMark(x: .value("Day", item.name), y: .value("Amount", item.amount))
                    .foregroundStyle(AppColors.danger(for: appColorMode).gradient)
            }
        }
    }

    @ViewBuilder
    private func renderComparisonChart(data: [ComparisonData], emptyMessage: String) -> some View {
        if data.isEmpty {
            WidgetEmptyStateView(message: emptyMessage)
        } else {
            Chart(data) { item in
                BarMark(x: .value("Period", item.period), y: .value("Amount", item.amount))
                    .foregroundStyle(by: .value("Type", item.type))
            }
        }
    }

    @ViewBuilder
    private func renderTopListChart(data: [ChartData], emptyMessage: String) -> some View {
        if data.isEmpty {
            WidgetEmptyStateView(message: emptyMessage)
        } else {
            Chart(data.prefix(10), id: \.name) { item in
                BarMark(x: .value("Amount", item.amount), y: .value("Name", item.name))
                    .foregroundStyle(AppColors.danger(for: appColorMode).gradient)
            }
            .chartXAxis(.hidden)
        }
    }

    @ViewBuilder
    private func renderIncomeVsExpensesChart() -> some View {
        let data = buildIncomeVsExpenses()
        if data.isEmpty {
            WidgetEmptyStateView(message: "No data")
        } else {
            Chart(data, id: \.name) { item in
                BarMark(x: .value("Type", item.name), y: .value("Amount", item.amount))
                    .foregroundStyle(item.name == "Income" ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
            }
        }
    }

    @ViewBuilder
    private func renderSavingsRateChart() -> some View {
        let rate = calculateSavingsRate()
        VStack(spacing: AppTheme.Spacing.tight) {
            Text("\(Int(rate))%")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(rate >= 20 ? AppColors.success(for: appColorMode) : (rate >= 10 ? AppColors.warning(for: appColorMode) : AppColors.danger(for: appColorMode)))
            Text("Savings Rate")
                .appCaptionText()
                .foregroundStyle(.secondary)
            ProgressView(value: min(rate / 100, 1.0))
                .tint(rate >= 20 ? AppColors.success(for: appColorMode) : (rate >= 10 ? AppColors.warning(for: appColorMode) : AppColors.danger(for: appColorMode)))
        }
        .padding()
    }

    @ViewBuilder
    private func renderBudgetPerformanceChart() -> some View {
        let data = buildBudgetPerformance()
        if data.isEmpty {
            WidgetEmptyStateView(message: "No budget data")
        } else {
            Chart(data) { item in
                BarMark(x: .value("Category", item.period), y: .value("Amount", item.amount))
                    .foregroundStyle(by: .value("Type", item.type))
            }
        }
    }

    @ViewBuilder
    private func renderCashFlowChart() -> some View {
        let data = buildCashFlow()
        if data.isEmpty {
            WidgetEmptyStateView(message: "No data")
        } else {
            Chart(data) { item in
                BarMark(x: .value("Date", item.date), y: .value("Amount", item.amount))
                    .foregroundStyle(item.amount >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
            }
        }
    }

    @ViewBuilder
    private func renderAverageTransactionChart() -> some View {
        let avg = calculateAverageTransaction()
        VStack(spacing: AppTheme.Spacing.tight) {
            Text(avg, format: .currency(code: currencyCode))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.primary)
            Text("Average Transaction")
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func renderFrequencyChart() -> some View {
        let data = buildTransactionFrequency()
        if data.isEmpty {
            WidgetEmptyStateView(message: "No data")
        } else {
            Chart(data, id: \.name) { item in
                BarMark(x: .value("Period", item.name), y: .value("Count", item.amount))
                    .foregroundStyle(AppColors.tint(for: appColorMode).gradient)
            }
        }
    }

    @ViewBuilder
    private func renderAccountBalancesChart() -> some View {
        let data = buildAccountBalances()
        if data.isEmpty {
            WidgetEmptyStateView(message: "No accounts")
        } else {
            Chart(data, id: \.name) { item in
                BarMark(x: .value("Account", item.name), y: .value("Balance", item.amount))
                    .foregroundStyle(AppColors.tint(for: appColorMode).gradient)
            }
        }
    }
    
    // MARK: - Table Rendering
    
    @ViewBuilder
    private func renderTable() -> some View {
        switch widget.dataType {
        case .transactions:
            VStack(spacing: 0) {
                ForEach(filteredTransactions.prefix(5)) { transaction in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(transaction.payee)
                                .appSecondaryBodyText()
                                .fontWeight(.medium)
                            Text(transaction.date, format: .dateTime.month().day())
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(transaction.amount, format: .currency(code: currencyCode))
                            .appSecondaryBodyText()
                            .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                    }
                    .padding(.vertical, AppTheme.Spacing.compact)
                    Divider()
                }
                if filteredTransactions.isEmpty {
                    Text("No transactions found")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            
        case .spendingByCategory:
            let data = buildCategorySpending()
            VStack(spacing: 0) {
                ForEach(data.prefix(5), id: \.name) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.amount, format: .currency(code: currencyCode))
                    }
                    .padding(.vertical, AppTheme.Spacing.compact)
                    Divider()
                }
            }
            
        default:
            Text("Table not implemented for this data type")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Data Helpers

    private struct ChartData {
        let name: String
        let amount: Decimal
    }

    private struct TimeSeriesData: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Decimal
    }

    private struct ComparisonData: Identifiable {
        let id = UUID()
        let period: String
        let type: String
        let amount: Decimal
    }

    // MARK: - Basic Data Builders

    private func buildCategorySpending() -> [ChartData] {
        var totals: [String: Decimal] = [:]
        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let cat = t.category?.name ?? "Uncategorized"
            totals[cat, default: 0] += abs(t.amount)
        }
        return totals.map { ChartData(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    private func buildIncomeSources() -> [ChartData] {
        var totals: [String: Decimal] = [:]
        for t in filteredTransactions where t.kind == .standard && t.amount > 0 {
            let source = t.payee.isEmpty ? "Unknown" : t.payee
            totals[source, default: 0] += t.amount
        }
        return totals.map { ChartData(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - Trend Data Builders

    private func buildSpendingTrend() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var dailyTotals: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let day = calendar.startOfDay(for: t.date)
            dailyTotals[day, default: 0] += abs(t.amount)
        }

        return dailyTotals.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func buildIncomeTrend() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var dailyTotals: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount > 0 {
            let day = calendar.startOfDay(for: t.date)
            dailyTotals[day, default: 0] += t.amount
        }

        return dailyTotals.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func buildCategoryTrendData() -> [TimeSeriesData] {
        // Get the top category and track it over time
        let topCategory = buildCategorySpending().first?.name ?? "Unknown"
        let calendar = Calendar.current
        var dailyTotals: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 && (t.category?.name ?? "Uncategorized") == topCategory {
            let day = calendar.startOfDay(for: t.date)
            dailyTotals[day, default: 0] += abs(t.amount)
        }

        return dailyTotals.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Pattern Data Builders

    private func buildDailyPattern() -> [ChartData] {
        let calendar = Calendar.current
        var dayTotals: [Int: Decimal] = [:]
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let weekday = calendar.component(.weekday, from: t.date) - 1
            dayTotals[weekday, default: 0] += abs(t.amount)
        }

        return dayNames.indices.map { index in
            ChartData(name: dayNames[index], amount: dayTotals[index] ?? 0)
        }
    }

    private func buildWeeklyPattern() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var weeklyTotals: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: t.date))!
            weeklyTotals[weekStart, default: 0] += abs(t.amount)
        }

        return weeklyTotals.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func buildMonthlyPattern() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var monthlyTotals: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: t.date))!
            monthlyTotals[monthStart, default: 0] += abs(t.amount)
        }

        return monthlyTotals.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Comparison Data Builders

    private func buildIncomeVsExpenses() -> [ChartData] {
        var income: Decimal = 0
        var expenses: Decimal = 0

        for t in filteredTransactions where t.kind == .standard {
            if t.amount > 0 {
                income += t.amount
            } else {
                expenses += abs(t.amount)
            }
        }

        return [
            ChartData(name: "Income", amount: income),
            ChartData(name: "Expenses", amount: expenses)
        ]
    }

    private func buildMonthOverMonth() -> [ComparisonData] {
        let calendar = Calendar.current
        let now = Date()
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!

        let thisMonth = transactionsCache.filter {
            $0.date >= thisMonthStart && $0.date <= now && $0.kind == .standard && $0.amount < 0
        }.reduce(Decimal.zero) { $0 + abs($1.amount) }

        let lastMonth = transactionsCache.filter {
            $0.date >= lastMonthStart && $0.date < thisMonthStart && $0.kind == .standard && $0.amount < 0
        }.reduce(Decimal.zero) { $0 + abs($1.amount) }

        return [
            ComparisonData(period: "Last Month", type: "Previous", amount: lastMonth),
            ComparisonData(period: "This Month", type: "Current", amount: thisMonth)
        ]
    }

    private func buildYearOverYear() -> [ComparisonData] {
        let calendar = Calendar.current
        let now = Date()
        let thisYearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
        let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYearStart)!

        let thisYear = transactionsCache.filter {
            $0.date >= thisYearStart && $0.date <= now && $0.kind == .standard && $0.amount < 0
        }.reduce(Decimal.zero) { $0 + abs($1.amount) }

        let lastYear = transactionsCache.filter {
            $0.date >= lastYearStart && $0.date < thisYearStart && $0.kind == .standard && $0.amount < 0
        }.reduce(Decimal.zero) { $0 + abs($1.amount) }

        return [
            ComparisonData(period: "Last Year", type: "Previous", amount: lastYear),
            ComparisonData(period: "This Year", type: "Current", amount: thisYear)
        ]
    }

    private func buildPeriodComparison() -> [ComparisonData] {
        // Compare last 4 quarters
        let calendar = Calendar.current
        let now = Date()
        var data: [ComparisonData] = []

        for i in 0..<4 {
            let quarterStart = calendar.date(byAdding: .month, value: -3 * (i + 1), to: now)!
            let quarterEnd = calendar.date(byAdding: .month, value: -3 * i, to: now)!

            let total = transactionsCache.filter {
                $0.date >= quarterStart && $0.date < quarterEnd && $0.kind == .standard && $0.amount < 0
            }.reduce(Decimal.zero) { $0 + abs($1.amount) }

            data.append(ComparisonData(period: "Q\(4-i)", type: "Quarter", amount: total))
        }

        return data.reversed()
    }

    // MARK: - Financial Health Data Builders

    private func buildNetWorthTrend() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var monthlyBalances: [Date: Decimal] = [:]

        for t in transactionsCache where t.kind == .standard {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: t.date))!
            monthlyBalances[monthStart, default: 0] += t.amount
        }

        var runningTotal: Decimal = 0
        return monthlyBalances.sorted { $0.key < $1.key }.map { date, amount in
            runningTotal += amount
            return TimeSeriesData(date: date, amount: runningTotal)
        }
    }

    private func calculateSavingsRate() -> Double {
        var income: Decimal = 0
        var expenses: Decimal = 0

        for t in filteredTransactions where t.kind == .standard {
            if t.amount > 0 {
                income += t.amount
            } else {
                expenses += abs(t.amount)
            }
        }

        guard income > 0 else { return 0 }
        let savings = income - expenses
        return Double(truncating: (savings / income * 100) as NSNumber)
    }

    private func buildBudgetPerformance() -> [ComparisonData] {
        var data: [ComparisonData] = []

        for group in categoryGroups where group.type == .expense {
            for category in group.sortedCategories {
                let budgeted = category.assigned
                let spent = filteredTransactions.filter {
                    $0.category?.persistentModelID == category.persistentModelID && $0.amount < 0
                }.reduce(Decimal.zero) { $0 + abs($1.amount) }

                data.append(ComparisonData(period: category.name, type: "Budgeted", amount: budgeted))
                data.append(ComparisonData(period: category.name, type: "Spent", amount: spent))
            }
        }

        return Array(data.prefix(20))
    }

    private func buildCashFlow() -> [TimeSeriesData] {
        let calendar = Calendar.current
        var monthlyFlow: [Date: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: t.date))!
            monthlyFlow[monthStart, default: 0] += t.amount
        }

        return monthlyFlow.map { TimeSeriesData(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Top Lists Data Builders

    private func buildTopExpenses() -> [ChartData] {
        return filteredTransactions
            .filter { $0.kind == .standard && $0.amount < 0 }
            .sorted { abs($0.amount) > abs($1.amount) }
            .prefix(10)
            .map { ChartData(name: $0.payee, amount: abs($0.amount)) }
    }

    private func buildTopCategories() -> [ChartData] {
        return buildCategorySpending().prefix(10).map { $0 }
    }

    private func buildTopMerchants() -> [ChartData] {
        var totals: [String: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let merchant = t.payee.isEmpty ? "Unknown" : t.payee
            totals[merchant, default: 0] += abs(t.amount)
        }

        return totals.map { ChartData(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(10)
            .map { $0 }
    }

    private func buildRecurringExpenses() -> [ChartData] {
        var merchantCounts: [String: Int] = [:]
        var merchantTotals: [String: Decimal] = [:]

        for t in filteredTransactions where t.kind == .standard && t.amount < 0 {
            let merchant = t.payee
            merchantCounts[merchant, default: 0] += 1
            merchantTotals[merchant, default: 0] += abs(t.amount)
        }

        // Find recurring (appears 3+ times)
        let recurring = merchantCounts.filter { $0.value >= 3 }
        return recurring.map { merchant, _ in
            ChartData(name: merchant, amount: merchantTotals[merchant] ?? 0)
        }.sorted { $0.amount > $1.amount }
    }

    // MARK: - Analytics Data Builders

    private func calculateAverageTransaction() -> Decimal {
        let expenses = filteredTransactions.filter { $0.kind == .standard && $0.amount < 0 }
        guard !expenses.isEmpty else { return 0 }
        let total = expenses.reduce(Decimal.zero) { $0 + abs($1.amount) }
        return total / Decimal(expenses.count)
    }

    private func buildTransactionFrequency() -> [ChartData] {
        let calendar = Calendar.current
        var monthlyCounts: [Date: Int] = [:]

        for t in filteredTransactions where t.kind == .standard {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: t.date))!
            monthlyCounts[monthStart, default: 0] += 1
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        return monthlyCounts.map { date, count in
            ChartData(name: formatter.string(from: date), amount: Decimal(count))
        }.sorted { $0.name < $1.name }
    }

    private func buildAccountBalances() -> [ChartData] {
        return accounts.map { account in
            ChartData(name: account.name, amount: account.balance)
        }
    }

    // MARK: - Upcoming Bills Widget

    @ViewBuilder
    private func renderUpcomingBillsView() -> some View {
        let upcomingBills = recurringPurchases
            .filter { $0.isActive }
            .prefix(5)

        if upcomingBills.isEmpty {
            WidgetEmptyStateView(message: "No upcoming bills")
        } else {
            VStack(spacing: AppTheme.Spacing.compact) {
                ForEach(Array(upcomingBills), id: \.id) { bill in
                    UpcomingBillRow(bill: bill, currencyCode: currencyCode, appColorMode: appColorMode)
                }
            }
            .padding(.vertical, AppTheme.Spacing.micro)
        }
    }
}

struct UpcomingBillRow: View {
    let bill: RecurringPurchase
    let currencyCode: String
    let appColorMode: AppColorMode

    private var daysUntil: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextDate = calendar.startOfDay(for: bill.nextDate)
        return calendar.dateComponents([.day], from: today, to: nextDate).day ?? 0
    }

    private var urgencyColor: Color {
        if daysUntil < 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil == 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil <= 3 {
            return AppColors.warning(for: appColorMode)
        } else if daysUntil <= 7 {
            return AppColors.tint(for: appColorMode)
        } else {
            return .secondary
        }
    }

    private var daysText: String {
        if daysUntil < 0 {
            return "Overdue"
        } else if daysUntil == 0 {
            return "Today"
        } else if daysUntil == 1 {
            return "Tomorrow"
        } else {
            return "in \(daysUntil)d"
        }
    }

	    var body: some View {
	        HStack(spacing: AppTheme.Spacing.compact) {
	            RoundedRectangle(cornerRadius: AppTheme.Radius.hairline)
	                .fill(urgencyColor)
	                .frame(width: 3)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                Text(bill.name)
                    .appCaptionText()
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(bill.nextDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppTheme.Spacing.hairline) {
                Text(bill.amount, format: .currency(code: currencyCode))
                    .appCaptionText()
                    .fontWeight(.semibold)

                Text(daysText)
                    .font(.caption2)
                    .foregroundStyle(urgencyColor)
            }
        }
	        .padding(.vertical, AppTheme.Spacing.micro)
	        .padding(.horizontal, AppTheme.Spacing.compact)
	        .background(Color(.secondarySystemBackground))
	        .cornerRadius(AppTheme.Radius.tag)
	    }
}

struct WidgetEmptyStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.3))
            Text(message)
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
