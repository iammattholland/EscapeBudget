import SwiftUI
import SwiftData
import Charts

// MARK: - Report Type

enum ReportType: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case spending = "Spending"
    case income = "Income"
    case trends = "Trends"
    case accounts = "Accounts"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .spending: return "arrow.down.circle.fill"
        case .income: return "arrow.up.circle.fill"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .accounts: return "building.columns.fill"
        }
    }
    
    func color(for mode: AppColorMode) -> Color {
        switch self {
        case .overview: return .purple
        case .spending: return AppColors.danger(for: mode)
        case .income: return AppColors.success(for: mode)
        case .trends: return AppColors.tint(for: mode)
        case .accounts: return AppColors.warning(for: mode)
        }
    }

    var color: Color {
        color(for: AppColors.currentModeFromDefaults())
    }
}

// MARK: - Data Models for Charts

struct CategorySpending: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let color: Color
}

struct DailyFlow: Identifiable {
    let id = UUID()
    let date: Date
    let income: Decimal
    let spending: Decimal
}

struct AccountBalance: Identifiable {
    let id = UUID()
    let name: String
    let balance: Decimal
    let type: AccountType
}

// MARK: - Main Reports View

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    // Date range state
    @State private var selectedDateRange: DateRangeType = .thisMonth
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    
    @State private var selectedReportType: ReportType = .overview
    @State private var animateCharts = false
    
    private var dateRange: (start: Date, end: Date) {
        selectedDateRange.dateRange(customStart: customStartDate, customEnd: customEndDate)
    }
    
    // Computed properties for filtered data
    private var filteredTransactions: [Transaction] {
        let range = dateRange
        return transactions.filter { $0.date >= range.start && $0.date <= range.end && $0.kind == .standard }
    }
    
    private var totalIncome: Decimal {
        filteredTransactions.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalSpending: Decimal {
        abs(filteredTransactions.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount })
    }
    
    private var netFlow: Decimal {
        totalIncome - totalSpending
    }
    
    private var totalBalance: Decimal {
        accounts.reduce(0) { $0 + $1.balance }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xLarge) {
                    // Date Range Selector
                    dateRangeHeader
                    
                    // Report Type Cards
                    reportTypeCards
                    
                    // Main Content Based on Selected Type
                    reportContent
                }
                .appAdaptiveScreenPadding()
                .appConstrainContentWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    animateCharts = true
                }
            }
        }
    }
    
    // MARK: - Date Range Header
    
    private var dateRangeHeader: some View {
        HStack {
            DateRangePicker(
                selectedRange: $selectedDateRange,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate
            )
            Spacer()
            DateRangeSummaryView(
                rangeType: selectedDateRange,
                customStart: customStartDate,
                customEnd: customEndDate
            )
        }
    }

    
    // MARK: - Report Type Cards
    
    private var reportTypeCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.medium) {
                ForEach(ReportType.allCases) { type in
                    ReportTypeCard(
                        type: type,
                        isSelected: selectedReportType == type
                    ) {
                        withAnimation(.spring(response: 0.4)) {
                            selectedReportType = type
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Report Content
    
    @ViewBuilder
    private var reportContent: some View {
        switch selectedReportType {
        case .overview:
            overviewReport
        case .spending:
            spendingReport
        case .income:
            incomeReport
        case .trends:
            trendsReport
        case .accounts:
            accountsReport
        }
    }
    
    // MARK: - Overview Report
    
    private var overviewReport: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Summary Cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.medium) {
                SummaryCard(
                    title: "Income",
                    value: totalIncome,
                    icon: "arrow.up.circle.fill",
                    color: AppColors.success(for: appColorMode),
                    animate: animateCharts
                )
                
                SummaryCard(
                    title: "Spending",
                    value: totalSpending,
                    icon: "arrow.down.circle.fill",
                    color: AppColors.danger(for: appColorMode),
                    animate: animateCharts
                )
                
                SummaryCard(
                    title: "Net Flow",
                    value: netFlow,
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: netFlow >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode),
                    animate: animateCharts
                )
                
                SummaryCard(
                    title: "Total Balance",
                    value: totalBalance,
                    icon: "banknote.fill",
                    color: AppColors.tint(for: appColorMode),
                    animate: animateCharts
                )
            }
            
            // Income vs Spending Chart
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Income vs Spending")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    if totalIncome > 0 || totalSpending > 0 {
                        Chart {
                            SectorMark(
                                angle: .value("Amount", animateCharts ? Double(truncating: totalIncome as NSNumber) : 0),
                                innerRadius: .ratio(0.6),
                                angularInset: 2
                            )
                            .foregroundStyle(AppColors.success(for: appColorMode).gradient)
                            .cornerRadius(AppTheme.Radius.xSmall)
                            
                            SectorMark(
                                angle: .value("Amount", animateCharts ? Double(truncating: totalSpending as NSNumber) : 0),
                                innerRadius: .ratio(0.6),
                                angularInset: 2
                            )
                            .foregroundStyle(AppColors.danger(for: appColorMode).gradient)
                            .cornerRadius(AppTheme.Radius.xSmall)
                        }
                        .frame(height: 200)
                        .chartLegend(position: .bottom)
                        
                        HStack(spacing: AppTheme.Spacing.xLarge) {
                            LegendItem(color: AppColors.success(for: appColorMode), label: "Income", value: totalIncome)
                            LegendItem(color: AppColors.danger(for: appColorMode), label: "Spending", value: totalSpending)
                        }
                    } else {
                        EmptyStateView(message: "No transactions in this period")
                    }
                }
            }
            
            // Recent Transactions Preview
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Recent Activity")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    if filteredTransactions.isEmpty {
                        EmptyStateView(message: "No transactions yet")
                    } else {
                        ForEach(Array(filteredTransactions.prefix(5).enumerated()), id: \.element.id) { index, transaction in
                            TransactionRowView(transaction: transaction)
                                .opacity(animateCharts ? 1 : 0)
                                .offset(y: animateCharts ? 0 : 20)
                                .animation(Animation.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: animateCharts)
                            
                            if index < min(4, filteredTransactions.count - 1) {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Spending Report
    
    private var spendingReport: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Total Spending Header
            GlassCard {
                VStack(spacing: 8) {
                    Text("Total Spending")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                    
                    Text(totalSpending, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.danger(for: appColorMode).gradient)
                }
            }
            
            // Spending by Category
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Spending by Category")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let categoryData = buildCategorySpending()
                    
                    if categoryData.isEmpty {
                        EmptyStateView(message: "No spending data available")
                    } else {
                        Chart(categoryData) { item in
                            SectorMark(
                                angle: .value("Amount", animateCharts ? Double(truncating: item.amount as NSNumber) : 0),
                                innerRadius: .ratio(0.5),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.color.gradient)
                            .cornerRadius(6)
                        }
                        .frame(height: 220)
                        
                        // Category breakdown
                        VStack(spacing: 12) {
                            ForEach(categoryData.sorted { $0.amount > $1.amount }) { category in
                                CategoryRow(
                                    name: category.name,
                                    amount: category.amount,
                                    total: totalSpending,
                                    color: category.color,
                                    animate: animateCharts
                                )
                            }
                        }
                    }
                }
            }
            
            // Top Spending Transactions
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Top Spending")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let topSpending = filteredTransactions
                        .filter { $0.amount < 0 }
                        .sorted { $0.amount < $1.amount }
                        .prefix(5)
                    
                    if topSpending.isEmpty {
                        EmptyStateView(message: "No spending transactions")
                    } else {
                        ForEach(Array(topSpending.enumerated()), id: \.element.id) { index, transaction in
                            TransactionRowView(transaction: transaction, showRank: index + 1)
                            if index < topSpending.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Income Report
    
    private var incomeReport: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Total Income Header
            GlassCard {
                VStack(spacing: 8) {
                    Text("Total Income")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                    
                    Text(totalIncome, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.success(for: appColorMode).gradient)
                }
            }
            
            // Income Sources
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Income Sources")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let incomeSources = buildIncomeSources()
                    
                    if incomeSources.isEmpty {
                        EmptyStateView(message: "No income data available")
                    } else {
                        Chart(incomeSources) { item in
                            BarMark(
                                x: .value("Amount", animateCharts ? Double(truncating: item.amount as NSNumber) : 0),
                                y: .value("Source", item.name)
                            )
                            .foregroundStyle(AppColors.success(for: appColorMode).gradient)
                            .cornerRadius(6)
                        }
                        .frame(height: CGFloat(incomeSources.count * 50 + 20))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(Decimal(amount), format: .currency(code: currencyCode).precision(.fractionLength(0)))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Top Income Transactions
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Top Income")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let topIncome = filteredTransactions
                        .filter { $0.amount > 0 }
                        .sorted { $0.amount > $1.amount }
                        .prefix(5)
                    
                    if topIncome.isEmpty {
                        EmptyStateView(message: "No income transactions")
                    } else {
                        ForEach(Array(topIncome.enumerated()), id: \.element.id) { index, transaction in
                            TransactionRowView(transaction: transaction, showRank: index + 1)
                            if index < topIncome.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Trends Report
    
    private var trendsReport: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Daily Cash Flow Chart
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Cash Flow Over Time")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let dailyData = buildDailyFlow()
                    
                    if dailyData.isEmpty {
                        EmptyStateView(message: "No transaction data for trends")
                    } else {
                        Chart(dailyData) { day in
                            LineMark(
                                x: .value("Date", day.date),
                                y: .value("Income", animateCharts ? Double(truncating: day.income as NSNumber) : 0)
                            )
                            .foregroundStyle(AppColors.success(for: appColorMode))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .symbol(Circle())
                            .symbolSize(30)
                            
                            LineMark(
                                x: .value("Date", day.date),
                                y: .value("Spending", animateCharts ? Double(truncating: day.spending as NSNumber) : 0)
                            )
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .symbol(Circle())
                            .symbolSize(30)
                            
                            AreaMark(
                                x: .value("Date", day.date),
                                y: .value("Income", animateCharts ? Double(truncating: day.income as NSNumber) : 0)
                            )
                            .foregroundStyle(AppColors.success(for: appColorMode).opacity(0.1))
                        }
                        .frame(height: 250)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: max(1, dailyData.count / 5))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        
                        HStack(spacing: AppTheme.Spacing.xLarge) {
                            HStack(spacing: 6) {
                                Circle().fill(AppColors.success(for: appColorMode)).frame(width: 8, height: 8)
                                Text("Income").appCaptionText().foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Circle().fill(AppColors.danger(for: appColorMode)).frame(width: 8, height: 8)
                                Text("Spending").appCaptionText().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Net Flow Trend
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Net Flow Trend")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let dailyData = buildDailyFlow()
                    
                    if dailyData.isEmpty {
                        EmptyStateView(message: "No data for net flow trend")
                    } else {
                        Chart(dailyData) { day in
                            let netFlow = day.income - day.spending
                            BarMark(
                                x: .value("Date", day.date),
                                y: .value("Net", animateCharts ? Double(truncating: netFlow as NSNumber) : 0)
                            )
                            .foregroundStyle(netFlow >= 0 ? AppColors.success(for: appColorMode).gradient : AppColors.danger(for: appColorMode).gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 180)
                    }
                }
            }
            
            // Statistics
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Statistics")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    let stats = calculateStatistics()
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.medium) {
                        StatRow(label: "Avg Daily Spending", value: stats.avgDailySpending)
                        StatRow(label: "Avg Transaction", value: stats.avgTransaction)
                        StatRow(label: "Total Transactions", count: stats.transactionCount)
                        StatRow(label: "Days with Activity", count: stats.activeDays)
                    }
                }
            }
        }
    }
    
    // MARK: - Accounts Report
    
    private var accountsReport: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Total Balance
            GlassCard {
                VStack(spacing: 8) {
                    Text("Total Balance")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                    
                    Text(totalBalance, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(totalBalance >= 0 ? AppColors.tint(for: appColorMode).gradient : AppColors.danger(for: appColorMode).gradient)
                }
            }
            
            // Account Distribution Chart
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Account Distribution")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    if accounts.isEmpty {
                        EmptyStateView(message: "No accounts yet")
                    } else {
                        Chart(accounts) { account in
                            SectorMark(
                                angle: .value("Balance", animateCharts ? max(Double(truncating: account.balance as NSNumber), 0) : 0),
                                innerRadius: .ratio(0.55),
                                angularInset: 2
                            )
                            .foregroundStyle(account.type.color.gradient)
                            .cornerRadius(AppTheme.Radius.xSmall)
                        }
                        .frame(height: 220)
                    }
                }
            }
            
            // Account List
            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Text("Account Details")
                        .appSectionTitleText()
                        .fontWeight(.semibold)
                    
                    if accounts.isEmpty {
                        EmptyStateView(message: "No accounts created")
                    } else {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            AccountRowView(
                                account: account,
                                color: account.type.color(for: appColorMode),
                                animate: animateCharts,
                                delay: Double(index) * 0.1
                            )
                            
                            if index < accounts.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func buildCategorySpending() -> [CategorySpending] {
        let colors: [Color] = [
            AppColors.danger(for: appColorMode),
            AppColors.warning(for: appColorMode),
            .yellow,
            AppColors.success(for: appColorMode),
            AppColors.tint(for: appColorMode),
            .purple,
            .pink,
            .teal
        ]
        var categoryTotals: [String: Decimal] = [:]
        
        for transaction in filteredTransactions where transaction.amount < 0 {
            let categoryName = transaction.category?.name ?? "Uncategorized"
            categoryTotals[categoryName, default: 0] += abs(transaction.amount)
        }
        
        return categoryTotals.enumerated().map { index, item in
            CategorySpending(
                name: item.key,
                amount: item.value,
                color: colors[index % colors.count]
            )
        }
    }
    
    private func buildIncomeSources() -> [CategorySpending] {
        var sourceTotals: [String: Decimal] = [:]
        
        for transaction in filteredTransactions where transaction.amount > 0 {
            let sourceName = transaction.payee.isEmpty ? "Unknown" : transaction.payee
            sourceTotals[sourceName, default: 0] += transaction.amount
        }
        
        return sourceTotals.map { CategorySpending(name: $0.key, amount: $0.value, color: AppColors.success(for: appColorMode)) }
            .sorted { $0.amount > $1.amount }
            .prefix(10)
            .map { $0 }
    }
    
    private func buildDailyFlow() -> [DailyFlow] {
        let calendar = Calendar.current
        var dailyData: [Date: (income: Decimal, spending: Decimal)] = [:]
        
        for transaction in filteredTransactions {
            let day = calendar.startOfDay(for: transaction.date)
            if transaction.amount > 0 {
                dailyData[day, default: (0, 0)].income += transaction.amount
            } else {
                dailyData[day, default: (0, 0)].spending += abs(transaction.amount)
            }
        }
        
        return dailyData.map { DailyFlow(date: $0.key, income: $0.value.income, spending: $0.value.spending) }
            .sorted { $0.date < $1.date }
    }
    
    private func calculateStatistics() -> (avgDailySpending: Decimal, avgTransaction: Decimal, transactionCount: Int, activeDays: Int) {
        let calendar = Calendar.current
        let uniqueDays = Set(filteredTransactions.map { calendar.startOfDay(for: $0.date) })
        
        let avgDaily = uniqueDays.isEmpty ? Decimal(0) : totalSpending / Decimal(uniqueDays.count)
        let avgTx = filteredTransactions.isEmpty ? Decimal(0) : 
            filteredTransactions.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(filteredTransactions.count)
        
        return (avgDaily, avgTx, filteredTransactions.count, uniqueDays.count)
    }
    


}

// MARK: - Supporting Views

struct ReportTypeCard: View {
    let type: ReportType
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .white : type.color(for: appColorMode))
                
                Text(type.rawValue)
                    .appCaptionText()
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(type.color(for: appColorMode).gradient) : AnyShapeStyle(Color(.systemBackground)))
                    .shadow(color: isSelected ? type.color(for: appColorMode).opacity(0.4) : .black.opacity(0.05), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(AppTheme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Decimal
    let icon: String
    let color: Color
    let animate: Bool
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color.gradient)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                
                Text(value, format: .currency(code: currencyCode))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(AppTheme.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        .scaleEffect(animate ? 1 : 0.8)
        .opacity(animate ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animate)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: Decimal
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                Text(value, format: .currency(code: currencyCode))
                    .appCaptionText()
                    .fontWeight(.semibold)
            }
        }
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    var showRank: Int? = nil
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        HStack(spacing: 12) {
            if let rank = showRank {
                Text("\(rank)")
                    .appCaptionText()
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppColors.tint(for: appColorMode)))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.payee)
                    .appSecondaryBodyText()
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    
                    if let category = transaction.category {
                        Text(category.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.tint(for: appColorMode).opacity(0.1)))
                            .foregroundColor(AppColors.tint(for: appColorMode))
                    }
                }
            }
            
            Spacer()
            
            Text(transaction.amount, format: .currency(code: currencyCode))
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundColor(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
        }
    }
}

struct CategoryRow: View {
    let name: String
    let amount: Decimal
    let total: Decimal
    let color: Color
    let animate: Bool
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(truncating: amount as NSNumber) / Double(truncating: total as NSNumber)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Text(name)
                        .appSecondaryBodyText()
                }
                
                Spacer()
                
                Text(amount, format: .currency(code: currencyCode))
                    .appSecondaryBodyText()
                    .fontWeight(.medium)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: animate ? geometry.size.width * percentage : 0)
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: animate)
                }
            }
            .frame(height: 8)
        }
    }
}

struct StatRow: View {
    let label: String
    var value: Decimal? = nil
    var count: Int? = nil
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .appCaptionText()
                .foregroundStyle(.secondary)
            
            if let value = value {
                Text(value, format: .currency(code: currencyCode))
                    .appSectionTitleText()
                    .fontWeight(.semibold)
            } else if let count = count {
                Text("\(count)")
                    .appSectionTitleText()
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact)
                .fill(Color(.systemGray6))
        )
    }
}

struct AccountRowView: View {
    let account: Account
    let color: Color
    let animate: Bool
    let delay: Double
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: account.type.icon)
                .font(.title2)
                .foregroundStyle(color.gradient)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact)
                        .fill(color.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .appSecondaryBodyText()
                    .fontWeight(.medium)
                
                Text(account.type.rawValue)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(account.balance, format: .currency(code: currencyCode))
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundColor(account.balance >= 0 ? .primary : AppColors.danger(for: appColorMode))
        }
        .opacity(animate ? 1 : 0)
        .offset(x: animate ? 0 : 20)
        .animation(.easeOut(duration: 0.4).delay(delay), value: animate)
    }
    

}

struct EmptyStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(message)
                .appSecondaryBodyText()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Preview

#Preview {
    ReportsView()
        .modelContainer(for: [Transaction.self, TransactionHistoryEntry.self, Account.self, Category.self, CategoryGroup.self, TransactionTag.self], inMemory: true)
}

#Preview("Reports • Dark") {
    ReportsView()
        .modelContainer(for: [Transaction.self, TransactionHistoryEntry.self, Account.self, Category.self, CategoryGroup.self, TransactionTag.self], inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("Reports • iPad") {
    ReportsView()
        .modelContainer(for: [Transaction.self, TransactionHistoryEntry.self, Account.self, Category.self, CategoryGroup.self, TransactionTag.self], inMemory: true)
        .preferredColorScheme(.dark)
        .previewDevice("iPad Pro (12.9-inch) (6th generation)")
}
