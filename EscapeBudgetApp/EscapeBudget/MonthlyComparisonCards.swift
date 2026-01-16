import SwiftUI
import SwiftData

struct MonthlySpendComparisonCard: View {
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Binding var referenceDate: Date
    @Environment(\.appColorMode) private var appColorMode

    @State private var extraMonths: [Date] = []
    @State private var showingMonthSelection = false
    @State private var pendingMonthSelection: Set<Date> = []
    @State private var showAverageLine = false
    @State private var showingAverageLineRequirement = false

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private var series: [MonthSeries] {
        var result: [MonthSeries] = []

        let currentStart = monthStart(for: referenceDate)
        result.append(MonthSeries(
            id: currentStart,
            title: Self.monthFormatter.string(from: currentStart),
            color: AppColors.danger(for: appColorMode),
            data: spendingSeries(for: referenceDate)
        ))

        if let previous = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) {
            let previousStart = monthStart(for: previous)
            result.append(MonthSeries(
                id: previousStart,
                title: Self.monthFormatter.string(from: previousStart),
                color: .gray,
                data: spendingSeries(for: previous)
            ))
        }

        let additionalColors: [Color] = [
            AppColors.tint(for: appColorMode),
            AppColors.success(for: appColorMode),
            AppColors.warning(for: appColorMode),
            .purple, .pink, .teal, .indigo
        ]
        let additionalSeries = extraMonths.enumerated().map { index, month -> MonthSeries in
            let start = monthStart(for: month)
            return MonthSeries(
                id: start,
                title: Self.monthFormatter.string(from: start),
                color: additionalColors[index % additionalColors.count],
                data: spendingSeries(for: start)
            )
        }

        result.append(contentsOf: additionalSeries)
        return result
    }

    private var hasSeriesData: Bool {
        series.contains { $0.data.contains { $0.cumulativeAmount != 0 } }
    }

    private var selectedMonthStarts: [Date] {
        var starts: [Date] = [monthStart(for: referenceDate)]
        if let previous = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) {
            starts.append(monthStart(for: previous))
        }
        starts.append(contentsOf: extraMonths.map { monthStart(for: $0) })
        return starts
    }

    private var completedMonthStartDates: [Date] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allTransactions.filter { $0.kind == .standard }) { monthStart(for: $0.date) }
        let now = Date()
        let toleranceDays = 2
        return grouped.compactMap { entry -> Date? in
            let start = entry.key
            guard let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
            guard now > end else { return nil }
            guard let earliest = entry.value.min(by: { $0.date < $1.date })?.date,
                  let latest = entry.value.max(by: { $0.date < $1.date })?.date else {
                return nil
            }
            guard let toleranceEnd = calendar.date(byAdding: .day, value: toleranceDays, to: start),
                  let toleranceStart = calendar.date(byAdding: .day, value: -toleranceDays, to: end) else {
                return nil
            }
            guard earliest <= toleranceEnd, latest >= toleranceStart else { return nil }
            return start
        }.sorted()
    }

    private var hasSufficientAverageData: Bool {
        completedMonthStartDates.count >= 2
    }

    private var averageLineData: [AverageSpendingPoint] {
        var aggregates: [Int: (sum: Decimal, count: Int)] = [:]
        let months = completedMonthStartDates
        guard months.count >= 2 else { return [] }

        for month in months {
            let points = spendingSeries(for: month)
            for point in points {
                var entry = aggregates[point.dayIndex] ?? (sum: 0, count: 0)
                entry.sum += point.cumulativeAmount
                entry.count += 1
                aggregates[point.dayIndex] = entry
            }
        }

        return aggregates.keys.sorted().compactMap { day in
            guard let entry = aggregates[day], entry.count > 0 else { return nil }
            let average = entry.sum / Decimal(entry.count)
            return AverageSpendingPoint(dayIndex: day, averageAmount: average)
        }
    }

    private var monthSelectionOptions: [Date] {
        let calendar = Calendar.current
        let selectedStarts = Set(selectedMonthStarts.map { monthStart(for: $0) })
        var options: [Date] = []
        for offset in 2...12 {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: referenceDate) else { continue }
            let start = monthStart(for: date)
            if !selectedStarts.contains(start), hasSpendingData(for: start) {
                options.append(start)
            }
        }
        return options
    }

    var body: some View {
        Group {
            if hasSeriesData {
                MonthComparisonLineChart(
                    title: "Monthly Spend",
                    subtitle: "Compare your spending across selected months.",
                    series: series,
                    showAverageLine: showAverageLine && hasSufficientAverageData,
                    averageLineData: averageLineData,
                    showsMenu: true,
                    useCardStyle: false
                ) {
                    Button("Add Month") { showingMonthSelection = true }
                        .disabled(monthSelectionOptions.isEmpty)

                    if !extraMonths.isEmpty {
                        Button("Reset to Current & Last", role: .destructive) {
                            extraMonths.removeAll()
                        }
                    }

                    Button(showAverageLine ? "Hide Monthly Average" : "Show Monthly Average") {
                        if showAverageLine {
                            showAverageLine = false
                        } else if hasSufficientAverageData {
                            showAverageLine = true
                        } else {
                            showingAverageLineRequirement = true
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly Spend")
                        .font(.headline)
                    Text("Not enough expense data yet. Add transactions to see trends.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingMonthSelection) {
            NavigationStack {
                List {
                    if monthSelectionOptions.isEmpty {
                        Text("All recent months are already shown.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(monthSelectionOptions, id: \.self) { month in
                            let label = Self.monthFormatter.string(from: month)
                            let normalized = monthStart(for: month)
                            Button {
                                toggleMonthSelection(normalized, selection: &pendingMonthSelection)
                            } label: {
                                HStack {
                                    Text(label)
                                    Spacer()
                                    if pendingMonthSelection.contains(normalized) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                .navigationTitle("Select Months")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingMonthSelection = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            addComparisonMonths(Array(pendingMonthSelection))
                            showingMonthSelection = false
                        }
                        .disabled(pendingMonthSelection.isEmpty)
                    }
                }
                .onAppear { pendingMonthSelection = [] }
            }
            .presentationDetents([.medium, .large])
            .solidPresentationBackground()
        }
        .alert("Monthly Average Unavailable", isPresented: $showingAverageLineRequirement) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("At least two complete months of data are required to show the monthly average.")
        }
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func hasSpendingData(for referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return false
        }
        return allTransactions.contains { $0.date >= monthStart && $0.date <= monthEnd && $0.kind == .standard && $0.amount < 0 }
    }

    private func spendingSeries(for referenceDate: Date) -> [DailySpending] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) else {
            return []
        }
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return []
        }

        let monthTransactions = allTransactions.filter { $0.date >= monthStart && $0.date <= monthEnd && $0.kind == .standard && $0.amount < 0 }
        var dailyTotals: [Int: Decimal] = [:]
        for transaction in monthTransactions {
            let day = calendar.component(.day, from: transaction.date)
            dailyTotals[day, default: 0] += abs(transaction.amount)
        }

        var cumulative: Decimal = 0
        var points: [DailySpending] = []
        let isCurrentMonth = calendar.isDate(monthStart, equalTo: Date(), toGranularity: .month)
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            if isCurrentMonth && date > Date() { break }
            cumulative += dailyTotals[day, default: 0]
            points.append(DailySpending(dayIndex: day, date: date, cumulativeAmount: cumulative))
        }
        return points
    }

    private func toggleMonthSelection(_ month: Date, selection: inout Set<Date>) {
        if selection.contains(month) {
            selection.remove(month)
        } else {
            selection.insert(month)
        }
    }

    private func addComparisonMonths(_ dates: [Date]) {
        for date in dates {
            let start = monthStart(for: date)
            let alreadyExists = extraMonths.contains { Calendar.current.isDate($0, equalTo: start, toGranularity: .month) }
            if !alreadyExists {
                extraMonths.append(start)
            }
        }
    }
}

struct MonthlyIncomeComparisonCard: View {
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Binding var referenceDate: Date
    @Environment(\.appColorMode) private var appColorMode

    @State private var extraMonths: [Date] = []
    @State private var showingMonthSelection = false
    @State private var pendingMonthSelection: Set<Date> = []
    @State private var showAverageLine = false
    @State private var showingAverageLineRequirement = false

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private var series: [MonthSeries] {
        var result: [MonthSeries] = []

        let currentStart = monthStart(for: referenceDate)
        result.append(MonthSeries(
            id: currentStart,
            title: Self.monthFormatter.string(from: currentStart),
            color: AppColors.success(for: appColorMode),
            data: incomeSeries(for: referenceDate)
        ))

        if let previous = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) {
            let previousStart = monthStart(for: previous)
            result.append(MonthSeries(
                id: previousStart,
                title: Self.monthFormatter.string(from: previousStart),
                color: .gray,
                data: incomeSeries(for: previous)
            ))
        }

        let additionalColors: [Color] = [
            AppColors.tint(for: appColorMode),
            AppColors.warning(for: appColorMode),
            .purple, .pink, .teal, .indigo
        ]
        let additionalSeries = extraMonths.enumerated().map { index, month -> MonthSeries in
            let start = monthStart(for: month)
            return MonthSeries(
                id: start,
                title: Self.monthFormatter.string(from: start),
                color: additionalColors[index % additionalColors.count],
                data: incomeSeries(for: start)
            )
        }

        result.append(contentsOf: additionalSeries)
        return result
    }

    private var hasSeriesData: Bool {
        series.contains { $0.data.contains { $0.cumulativeAmount != 0 } }
    }

    private var selectedMonthStarts: [Date] {
        var starts: [Date] = [monthStart(for: referenceDate)]
        if let previous = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) {
            starts.append(monthStart(for: previous))
        }
        starts.append(contentsOf: extraMonths.map { monthStart(for: $0) })
        return starts
    }

    private var completedMonthStartDates: [Date] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allTransactions.filter { $0.kind == .standard }) { monthStart(for: $0.date) }
        let now = Date()
        let toleranceDays = 2
        return grouped.compactMap { entry -> Date? in
            let start = entry.key
            guard let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
            guard now > end else { return nil }
            guard let earliest = entry.value.min(by: { $0.date < $1.date })?.date,
                  let latest = entry.value.max(by: { $0.date < $1.date })?.date else {
                return nil
            }
            guard let toleranceEnd = calendar.date(byAdding: .day, value: toleranceDays, to: start),
                  let toleranceStart = calendar.date(byAdding: .day, value: -toleranceDays, to: end) else {
                return nil
            }
            guard earliest <= toleranceEnd, latest >= toleranceStart else { return nil }
            return start
        }.sorted()
    }

    private var hasSufficientAverageData: Bool {
        completedMonthStartDates.count >= 2
    }

    private var averageLineData: [AverageSpendingPoint] {
        var aggregates: [Int: (sum: Decimal, count: Int)] = [:]
        let months = completedMonthStartDates
        guard months.count >= 2 else { return [] }

        for month in months {
            let points = incomeSeries(for: month)
            for point in points {
                var entry = aggregates[point.dayIndex] ?? (sum: 0, count: 0)
                entry.sum += point.cumulativeAmount
                entry.count += 1
                aggregates[point.dayIndex] = entry
            }
        }

        return aggregates.keys.sorted().compactMap { day in
            guard let entry = aggregates[day], entry.count > 0 else { return nil }
            let average = entry.sum / Decimal(entry.count)
            return AverageSpendingPoint(dayIndex: day, averageAmount: average)
        }
    }

    private var monthSelectionOptions: [Date] {
        let calendar = Calendar.current
        let selectedStarts = Set(selectedMonthStarts.map { monthStart(for: $0) })
        var options: [Date] = []
        for offset in 2...12 {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: referenceDate) else { continue }
            let start = monthStart(for: date)
            if !selectedStarts.contains(start), hasIncomeData(for: start) {
                options.append(start)
            }
        }
        return options
    }

    var body: some View {
        Group {
            if hasSeriesData {
                MonthlyIncomeBarChart(
                    title: "Monthly Income",
                    subtitle: "See income occurrences across selected months.",
                    series: series,
                    showAverageLine: showAverageLine && hasSufficientAverageData,
                    averageLineData: averageLineData,
                    addMonthAction: { showingMonthSelection = true },
                    resetAction: !extraMonths.isEmpty ? { extraMonths.removeAll() } : nil,
                    toggleAverage: {
                        if showAverageLine {
                            showAverageLine = false
                        } else if hasSufficientAverageData {
                            showAverageLine = true
                        } else {
                            showingAverageLineRequirement = true
                        }
                    },
                    canAddMonth: !monthSelectionOptions.isEmpty,
                    useCardStyle: false
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly Income")
                        .font(.headline)
                    Text("Not enough income data yet. Add transactions to see trends.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingMonthSelection) {
            NavigationStack {
                List {
                    if monthSelectionOptions.isEmpty {
                        Text("All recent months are already shown.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(monthSelectionOptions, id: \.self) { month in
                            let label = Self.monthFormatter.string(from: month)
                            let normalized = monthStart(for: month)
                            Button {
                                toggleMonthSelection(normalized, selection: &pendingMonthSelection)
                            } label: {
                                HStack {
                                    Text(label)
                                    Spacer()
                                    if pendingMonthSelection.contains(normalized) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                .navigationTitle("Select Months")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingMonthSelection = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            addComparisonMonths(Array(pendingMonthSelection))
                            showingMonthSelection = false
                        }
                        .disabled(pendingMonthSelection.isEmpty)
                    }
                }
                .onAppear { pendingMonthSelection = [] }
            }
            .presentationDetents([.medium, .large])
            .solidPresentationBackground()
        }
        .alert("Monthly Average Unavailable", isPresented: $showingAverageLineRequirement) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("At least two complete months of data are required to show the monthly average.")
        }
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func hasIncomeData(for referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return false
        }
        return allTransactions.contains { $0.date >= monthStart && $0.date <= monthEnd && $0.kind == .standard && $0.amount > 0 }
    }

    private func incomeSeries(for referenceDate: Date) -> [DailySpending] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) else {
            return []
        }
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return []
        }

        let monthTransactions = allTransactions.filter { $0.date >= monthStart && $0.date <= monthEnd && $0.kind == .standard && $0.amount > 0 }
        var dailyTotals: [Int: Decimal] = [:]
        for transaction in monthTransactions {
            let day = calendar.component(.day, from: transaction.date)
            dailyTotals[day, default: 0] += transaction.amount
        }

        var cumulative: Decimal = 0
        var points: [DailySpending] = []
        let isCurrentMonth = calendar.isDate(monthStart, equalTo: Date(), toGranularity: .month)
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            if isCurrentMonth && date > Date() { break }
            cumulative += dailyTotals[day, default: 0]
            points.append(DailySpending(dayIndex: day, date: date, cumulativeAmount: cumulative))
        }
        return points
    }

    private func toggleMonthSelection(_ month: Date, selection: inout Set<Date>) {
        if selection.contains(month) {
            selection.remove(month)
        } else {
            selection.insert(month)
        }
    }

    private func addComparisonMonths(_ dates: [Date]) {
        for date in dates {
            let start = monthStart(for: date)
            let alreadyExists = extraMonths.contains { Calendar.current.isDate($0, equalTo: start, toGranularity: .month) }
            if !alreadyExists {
                extraMonths.append(start)
            }
        }
    }
}
