import SwiftUI
import SwiftData

struct WidgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    @Binding var widget: CustomDashboardWidget?
    @State private var isNew: Bool

    // Temporary state for editing
    @State private var title: String = ""
    @State private var widgetType: WidgetType = .chart
    @State private var chartType: ChartType = .bar
    @State private var dataType: WidgetDataType = .spendingByCategory
    @State private var dateRange: WidgetDateRange = .thisMonth
    @State private var showingSuggestedWidgets = false

    init(widget: Binding<CustomDashboardWidget?>) {
        self._widget = widget
        self._isNew = State(initialValue: widget.wrappedValue == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        Button {
                            showingSuggestedWidgets = true
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(AppColors.tint(for: appColorMode))
                                Text("Browse Suggested Widgets")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Quick Start")
                    } footer: {
                        Text("Choose from pre-configured widgets for common insights")
                    }
                }

                Section("Widget Details") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $widgetType) {
                        ForEach(WidgetType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Data Source", selection: $dataType) {
                        ForEach(WidgetDataType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Picker("Date Range", selection: $dateRange) {
                        ForEach(WidgetDateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                } header: {
                    Text("Data Configuration")
                } footer: {
                    Text(dataType.description)
                }

                if widgetType == .chart {
                    Section("Chart Style") {
                        Picker("Chart Type", selection: $chartType) {
                            ForEach(ChartType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(isNew ? "New Widget" : "Edit Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveWidget() }
                        .disabled(title.isEmpty)
                }
            }
            .sheet(isPresented: $showingSuggestedWidgets) {
                SuggestedWidgetsView { template in
                    applyTemplate(template)
                    showingSuggestedWidgets = false
                }
            }
            .onAppear {
                if let existingWidget = widget {
                    title = existingWidget.title
                    widgetType = existingWidget.widgetType
                    chartType = existingWidget.chartType
                    dataType = existingWidget.dataType
                    dateRange = existingWidget.dateRange
                    isNew = false
                } else {
                    title = "New Widget"
                    isNew = true
                }
            }
        }
    }

    private func saveWidget() {
        if let existingWidget = widget {
            existingWidget.title = title
            existingWidget.widgetType = widgetType
            existingWidget.chartType = chartType
            existingWidget.dataType = dataType
            existingWidget.dateRange = dateRange
        } else {
            let newWidget = CustomDashboardWidget(
                title: title,
                widgetType: widgetType,
                chartType: chartType,
                dataType: dataType,
                dateRange: dateRange
            )
            modelContext.insert(newWidget)
        }

        guard modelContext.safeSave(context: "WidgetEditorView.saveWidget") else { return }
        dismiss()
    }

    private func applyTemplate(_ template: WidgetTemplate) {
        title = template.title
        widgetType = template.widgetType
        chartType = template.chartType
        dataType = template.dataType
        dateRange = template.dateRange
    }
}

// MARK: - Widget Templates

struct WidgetTemplate: Identifiable {
    let id = UUID()
    let title: String
    let dataType: WidgetDataType
    let widgetType: WidgetType
    let chartType: ChartType
    let dateRange: WidgetDateRange

    static let templates: [WidgetTemplate] = [
        // Basic
        WidgetTemplate(title: "Spending by Category", dataType: .spendingByCategory, widgetType: .chart, chartType: .pie, dateRange: .thisMonth),
        WidgetTemplate(title: "Income Sources", dataType: .incomeBySource, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Recent Transactions", dataType: .transactions, widgetType: .table, chartType: .bar, dateRange: .thisWeek),

        // Trends & Patterns
        WidgetTemplate(title: "Monthly Spending Trend", dataType: .spendingTrend, widgetType: .chart, chartType: .line, dateRange: .last6Months),
        WidgetTemplate(title: "Income Over Time", dataType: .incomeTrend, widgetType: .chart, chartType: .line, dateRange: .last6Months),
        WidgetTemplate(title: "Top Category Trend", dataType: .categoryTrend, widgetType: .chart, chartType: .line, dateRange: .last3Months),
        WidgetTemplate(title: "Spending by Day of Week", dataType: .dailySpendingPattern, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Weekly Spending Pattern", dataType: .weeklySpendingPattern, widgetType: .chart, chartType: .line, dateRange: .last3Months),
        WidgetTemplate(title: "Monthly Comparison", dataType: .monthlySpendingPattern, widgetType: .chart, chartType: .bar, dateRange: .last12Months),

        // Comparisons
        WidgetTemplate(title: "Income vs Expenses", dataType: .incomeVsExpenses, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "This Month vs Last Month", dataType: .monthOverMonth, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Year-over-Year Comparison", dataType: .yearOverYear, widgetType: .chart, chartType: .bar, dateRange: .yearToDate),
        WidgetTemplate(title: "Quarterly Trends", dataType: .periodComparison, widgetType: .chart, chartType: .bar, dateRange: .last12Months),

        // Financial Health
        WidgetTemplate(title: "Net Worth Growth", dataType: .netWorthOverTime, widgetType: .chart, chartType: .line, dateRange: .last12Months),
        WidgetTemplate(title: "Savings Rate", dataType: .savingsRate, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Budget vs Actual", dataType: .budgetPerformance, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Monthly Cash Flow", dataType: .cashFlow, widgetType: .chart, chartType: .bar, dateRange: .last6Months),

        // Top Lists
        WidgetTemplate(title: "Top 10 Expenses", dataType: .topExpenses, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Highest Spending Categories", dataType: .topCategories, widgetType: .chart, chartType: .pie, dateRange: .thisMonth),
        WidgetTemplate(title: "Most Frequent Merchants", dataType: .topMerchants, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Recurring Subscriptions", dataType: .recurringExpenses, widgetType: .chart, chartType: .bar, dateRange: .last3Months),

        // Analytics
        WidgetTemplate(title: "Average Transaction Size", dataType: .averageTransaction, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Transaction Frequency", dataType: .transactionFrequency, widgetType: .chart, chartType: .bar, dateRange: .last6Months),
        WidgetTemplate(title: "Category Distribution", dataType: .categoryDistribution, widgetType: .chart, chartType: .pie, dateRange: .thisMonth),
        WidgetTemplate(title: "Account Balances", dataType: .accountBalances, widgetType: .chart, chartType: .bar, dateRange: .thisMonth),
        WidgetTemplate(title: "Upcoming Bills", dataType: .upcomingBills, widgetType: .table, chartType: .bar, dateRange: .thisMonth),
    ]
}

// MARK: - Suggested Widgets View

struct SuggestedWidgetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    let onSelect: (WidgetTemplate) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(WidgetCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(templatesFor(category: category)) { template in
                            Button {
                                onSelect(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: iconFor(dataType: template.dataType))
                                            .foregroundColor(AppColors.tint(for: appColorMode))
                                            .frame(width: 24)

                                        Text(template.title)
                                            .foregroundStyle(.primary)
                                            .fontWeight(.medium)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(template.dataType.description)
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, AppTheme.Spacing.xxLarge)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Suggested Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func templatesFor(category: WidgetCategory) -> [WidgetTemplate] {
        WidgetTemplate.templates.filter { $0.dataType.category == category }
    }

    private func iconFor(dataType: WidgetDataType) -> String {
        switch dataType.category {
        case .basic: return "chart.bar"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .comparisons: return "arrow.left.arrow.right"
        case .financial: return "dollarsign.circle"
        case .topLists: return "list.number"
        case .analytics: return "chart.xyaxis.line"
        }
    }
}
