import SwiftUI
import Charts

struct DailySpending: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let date: Date
    let cumulativeAmount: Decimal
}

struct MonthSeries: Identifiable {
    let id: Date
    let title: String
    let color: Color
    let data: [DailySpending]
}

struct AverageSpendingPoint: Identifiable {
    let dayIndex: Int
    let averageAmount: Decimal
    var id: Int { dayIndex }
}

struct MonthComparisonLineChart<MenuContent: View>: View {
    let title: String
    let subtitle: String?
    let series: [MonthSeries]
    let showAverageLine: Bool
    let averageLineData: [AverageSpendingPoint]
    let showsMenu: Bool
    var useCardStyle: Bool = true
    @ViewBuilder let menuContent: () -> MenuContent

    private let lastUsedCurrencyCode = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDay: Int? = nil

    private var orderedSeries: [MonthSeries] {
        series.sorted { $0.id > $1.id }
    }

    private var primarySeries: MonthSeries? {
        orderedSeries.first
    }

    private var selectedPoint: (series: MonthSeries, point: DailySpending)? {
        guard let day = selectedDay, let primarySeries else { return nil }
        guard let point = primarySeries.data.min(by: { abs($0.dayIndex - day) < abs($1.dayIndex - day) }) else { return nil }
        return (primarySeries, point)
    }

    private var yMax: Decimal {
        let allValues = series.flatMap { month -> [Decimal] in
            month.data.map { $0.cumulativeAmount }
        }
        return allValues.max() ?? 0
    }

    private var averageLineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color(.darkGray)
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .appSectionTitleText()
                    if let subtitle {
                        Text(subtitle)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if showsMenu {
                    Menu { menuContent() } label: {
                        Image(systemName: "ellipsis")
                            .appDisplayText(AppDesign.Theme.DisplaySize.small, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if series.allSatisfy({ $0.data.isEmpty }) {
                Text("Not enough data yet. Add transactions to see trends.")
                    .appFootnoteText()
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppDesign.Theme.Spacing.xLarge)
            } else {
                Chart {
                    ForEach(orderedSeries) { monthSeries in
                        ForEach(monthSeries.data) { point in
                            LineMark(
                                x: .value("Day", point.dayIndex),
                                y: .value("Spend", NSDecimalNumber(decimal: point.cumulativeAmount).doubleValue),
                                series: .value("Month", monthSeries.title)
                            )
                            .foregroundStyle(monthSeries.color)
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    if showAverageLine {
                        ForEach(averageLineData) { point in
                            LineMark(
                                x: .value("Day", point.dayIndex),
                                y: .value("Average Spend", NSDecimalNumber(decimal: point.averageAmount).doubleValue)
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .foregroundStyle(averageLineColor)
                        }
                    }
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
                                            if let day: Int = proxy.value(atX: locationX) {
                                                selectedDay = day
                                            }
                                        }
                                )

                            if let selectedPoint,
                               let plotFrameAnchor = proxy.plotFrame,
                               let xPosition = proxy.position(forX: selectedPoint.point.dayIndex),
                               let yPosition = proxy.position(forY: NSDecimalNumber(decimal: selectedPoint.point.cumulativeAmount).doubleValue) {
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
                                    .fill(selectedPoint.series.color)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                    .position(x: x, y: y)
                                    .zIndex(2)

                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                    Text(selectedPoint.series.title)
                                        .appCaption2Text()
                                        .foregroundStyle(.secondary)
                                    Text("Day \(selectedPoint.point.dayIndex)")
                                        .appCaption2Text()
                                        .foregroundStyle(.secondary)
                                    Text(selectedPoint.point.cumulativeAmount, format: .currency(code: lastUsedCurrencyCode))
                                        .appCaptionText()
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, AppDesign.Theme.Spacing.compact)
                                .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
                                .background(
                                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.button, style: .continuous)
                                        .fill(Color(.systemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.button, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                                .offset(x: min(max(0, x - plotFrame.minX - 80), plotFrame.width - 160), y: -8)
                                .zIndex(3)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        if let doubleValue = value.as(Double.self) {
                            AxisValueLabel {
                                Text(doubleValue, format: .currency(code: lastUsedCurrencyCode))
                                    .appCaption2Text()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...(yMax == 0 ? 1 : yMax))
                .frame(height: 200)
                .onAppear {
                    if selectedDay == nil, let last = primarySeries?.data.last?.dayIndex {
                        selectedDay = last
                    }
                }
            }

            if !orderedSeries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppDesign.Theme.Spacing.tight) {
                        ForEach(orderedSeries) { monthSeries in
                            SpendingLegendItem(color: monthSeries.color, label: monthSeries.title)
                        }
                    }
                }
            }
        }

        if useCardStyle {
            content
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(AppDesign.Theme.Radius.compact)
                .shadow(color: Color.black.opacity(0.1), radius: 4)
        } else {
            content
        }
    }
}

extension MonthComparisonLineChart where MenuContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        series: [MonthSeries],
        showAverageLine: Bool = false,
        averageLineData: [AverageSpendingPoint] = [],
        showsMenu: Bool = false,
        useCardStyle: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.series = series
        self.showAverageLine = showAverageLine
        self.averageLineData = averageLineData
        self.showsMenu = showsMenu
        self.useCardStyle = useCardStyle
        self.menuContent = { EmptyView() }
    }
}

struct MonthlyIncomeBarChart: View {
    let title: String
    let subtitle: String?
    let series: [MonthSeries]
    let showAverageLine: Bool
    let averageLineData: [AverageSpendingPoint]
    let addMonthAction: () -> Void
    let resetAction: (() -> Void)?
    let toggleAverage: () -> Void
    let canAddMonth: Bool
    var useCardStyle: Bool = true

    private let currencyCode = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"

    private var orderedSeries: [MonthSeries] {
        series.sorted { $0.id < $1.id }
    }

    private var monthlyTotals: [(month: String, total: Decimal, color: Color)] {
        orderedSeries.map { monthSeries in
            let total = monthSeries.data.last?.cumulativeAmount ?? 0
            return (month: monthSeries.title, total: total, color: monthSeries.color)
        }
    }

    private var maxIncomeValue: Double {
        let maxTotal = monthlyTotals.map { NSDecimalNumber(decimal: $0.total).doubleValue }.max() ?? 0
        let averageValue = NSDecimalNumber(decimal: averageMonthlyIncome).doubleValue
        let maxValue = max(maxTotal, averageValue)
        return maxValue == 0 ? 1 : maxValue
    }

    private var averageMonthlyIncome: Decimal {
        let totals = monthlyTotals.map { $0.total }
        return totals.isEmpty ? 0 : totals.reduce(0, +) / Decimal(totals.count)
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .appSectionTitleText()
                    if let subtitle {
                        Text(subtitle)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Add Month", action: addMonthAction)
                        .disabled(!canAddMonth)

                    if let resetAction {
                        Button("Reset to Current & Last", role: .destructive, action: resetAction)
                    }

                    Button(showAverageLine ? "Hide Monthly Average" : "Show Monthly Average", action: toggleAverage)
                } label: {
                    Image(systemName: "ellipsis")
                        .appDisplayText(AppDesign.Theme.DisplaySize.small, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            if monthlyTotals.isEmpty || monthlyTotals.allSatisfy({ $0.total == 0 }) {
                Text("Not enough income data yet. Add transactions to see trends.")
                    .appFootnoteText()
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppDesign.Theme.Spacing.xLarge)
            } else {
                Chart {
                    ForEach(monthlyTotals, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.month),
                            y: .value("Income", NSDecimalNumber(decimal: item.total).doubleValue)
                        )
                        .foregroundStyle(item.color)
                    }

                    if showAverageLine {
                        RuleMark(
                            y: .value("Average", NSDecimalNumber(decimal: averageMonthlyIncome).doubleValue)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(Color.gray)
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        if let doubleValue = value.as(Double.self) {
                            AxisValueLabel {
                                Text(doubleValue, format: .currency(code: currencyCode))
                                    .appCaption2Text()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...maxIncomeValue)
                .frame(height: 200)
            }

            if !orderedSeries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppDesign.Theme.Spacing.tight) {
                        ForEach(orderedSeries) { monthSeries in
                            SpendingLegendItem(color: monthSeries.color, label: monthSeries.title)
                        }
                    }
                }
            }
        }

        if useCardStyle {
            content
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(AppDesign.Theme.Radius.compact)
                .shadow(color: Color.black.opacity(0.1), radius: 4)
        } else {
            content
        }
    }
}

private struct SpendingLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
    }
}
