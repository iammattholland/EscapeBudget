import SwiftUI
import SwiftData

@Model
final class CustomDashboardWidget: DemoDataTrackable {
    var id: UUID
    var title: String
    var order: Int
    var widgetType: WidgetType
    var chartType: ChartType
    var dataType: WidgetDataType
    var dateRange: WidgetDateRange
    var isDemoData: Bool = false
    
    init(
        title: String = "New Widget",
        order: Int = 0,
        widgetType: WidgetType = .chart,
        chartType: ChartType = .bar,
        dataType: WidgetDataType = .spendingByCategory,
        dateRange: WidgetDateRange = .thisMonth,
        isDemoData: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.widgetType = widgetType
        self.chartType = chartType
        self.dataType = dataType
        self.dateRange = dateRange
        self.isDemoData = isDemoData
    }
}

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case chart = "Chart"
    case table = "Table"
    
    var id: String { rawValue }
}

enum ChartType: String, Codable, CaseIterable, Identifiable {
    case bar = "Bar"
    case line = "Line"
    case pie = "Pie"
    
    var id: String { rawValue }
}

enum WidgetDataType: String, Codable, CaseIterable, Identifiable {
    // Basic Views
    case transactions = "Transactions"
    case spendingByCategory = "Spending by Category"
    case incomeBySource = "Income by Source"

    // Trends & Patterns
    case spendingTrend = "Spending Trend"
    case incomeTrend = "Income Trend"
    case categoryTrend = "Category Spending Trend"
    case dailySpendingPattern = "Daily Spending Pattern"
    case weeklySpendingPattern = "Weekly Spending Pattern"
    case monthlySpendingPattern = "Monthly Spending Pattern"

    // Comparisons
    case incomeVsExpenses = "Income vs Expenses"
    case monthOverMonth = "Month-over-Month"
    case yearOverYear = "Year-over-Year"
    case periodComparison = "Period Comparison"

    // Financial Health
    case netWorthOverTime = "Net Worth Trend"
    case savingsRate = "Savings Rate"
    case budgetPerformance = "Budget Performance"
    case cashFlow = "Cash Flow"

    // Top Lists
    case topExpenses = "Top Expenses"
    case topCategories = "Top Categories"
    case topMerchants = "Top Merchants"
    case recurringExpenses = "Recurring Expenses"

    // Analytics
    case averageTransaction = "Average Transaction Size"
    case transactionFrequency = "Transaction Frequency"
    case categoryDistribution = "Category Distribution"
    case accountBalances = "Account Balances"
    case upcomingBills = "Upcoming Bills"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .transactions: return "List of recent transactions"
        case .spendingByCategory: return "Breakdown of spending by category"
        case .incomeBySource: return "Income grouped by source"
        case .spendingTrend: return "How spending changes over time"
        case .incomeTrend: return "How income changes over time"
        case .categoryTrend: return "Track a specific category over time"
        case .dailySpendingPattern: return "Spending by day of week"
        case .weeklySpendingPattern: return "Spending by week"
        case .monthlySpendingPattern: return "Spending by month"
        case .incomeVsExpenses: return "Compare income and expenses"
        case .monthOverMonth: return "Compare current month to previous"
        case .yearOverYear: return "Compare to same period last year"
        case .periodComparison: return "Compare multiple time periods"
        case .netWorthOverTime: return "Net worth progression"
        case .savingsRate: return "Percentage of income saved"
        case .budgetPerformance: return "Actual vs budgeted amounts"
        case .cashFlow: return "Money in vs money out"
        case .topExpenses: return "Largest individual expenses"
        case .topCategories: return "Categories with most spending"
        case .topMerchants: return "Most frequent merchants"
        case .recurringExpenses: return "Identify recurring payments"
        case .averageTransaction: return "Average transaction amount"
        case .transactionFrequency: return "How often you spend"
        case .categoryDistribution: return "Percentage breakdown by category"
        case .accountBalances: return "Current account balances"
        case .upcomingBills: return "Upcoming recurring bills and due dates"
        }
    }

    var category: WidgetCategory {
        switch self {
        case .transactions, .spendingByCategory, .incomeBySource:
            return .basic
        case .spendingTrend, .incomeTrend, .categoryTrend, .dailySpendingPattern, .weeklySpendingPattern, .monthlySpendingPattern:
            return .trends
        case .incomeVsExpenses, .monthOverMonth, .yearOverYear, .periodComparison:
            return .comparisons
        case .netWorthOverTime, .savingsRate, .budgetPerformance, .cashFlow:
            return .financial
        case .topExpenses, .topCategories, .topMerchants, .recurringExpenses:
            return .topLists
        case .averageTransaction, .transactionFrequency, .categoryDistribution, .accountBalances, .upcomingBills:
            return .analytics
        }
    }
}

enum WidgetCategory: String, CaseIterable {
    case basic = "Basic"
    case trends = "Trends & Patterns"
    case comparisons = "Comparisons"
    case financial = "Financial Health"
    case topLists = "Top Lists"
    case analytics = "Analytics"
}

enum WidgetDateRange: String, Codable, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case last6Months = "Last 6 Months"
    case thisYear = "This Year"
    case lastYear = "Last Year"
    case yearToDate = "Year to Date"
    case last12Months = "Last 12 Months"
    case allTime = "All Time"

    var id: String { rawValue }
    
    func dateRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .thisWeek:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return (start, now)

        case .lastWeek:
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            let lastWeekEnd = calendar.date(byAdding: .day, value: -1, to: thisWeekStart)!
            return (lastWeekStart, lastWeekEnd)

        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return (start, now)

        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonth))!
            let end = calendar.date(byAdding: .day, value: -1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)!
            return (start, end)

        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now)!
            return (start, now)

        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: now)!
            return (start, now)

        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return (start, now)

        case .lastYear:
            let thisYearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYearStart)!
            let lastYearEnd = calendar.date(byAdding: .day, value: -1, to: thisYearStart)!
            return (lastYearStart, lastYearEnd)

        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return (start, now)

        case .last12Months:
            let start = calendar.date(byAdding: .month, value: -12, to: now)!
            return (start, now)

        case .allTime:
            return (.distantPast, now)
        }
    }
}
