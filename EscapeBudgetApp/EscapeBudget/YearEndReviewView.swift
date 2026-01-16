import SwiftUI
import SwiftData
import Charts

struct YearEndReviewView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingWrapped = false
    @State private var showingAddTransaction = false

    private var availableYears: [Int] {
        let years = allTransactions.map { Calendar.current.component(.year, from: $0.date) }
        return Array(Set(years)).sorted()
    }

    private var effectiveYear: Int {
        if availableYears.contains(selectedYear) { return selectedYear }
        return availableYears.last ?? selectedYear
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if availableYears.isEmpty {
                    EmptyDataCard(
                        systemImage: "sparkles",
                        title: "No Year-End Review Yet",
                        message: "Add your first transaction to start generating a year-end recap.",
                        actionTitle: "Add Transaction",
                        action: { showingAddTransaction = true }
                    )
                } else {
                    YearEndHeaderCard(
                        year: effectiveYear,
                        availableYears: availableYears,
                        onPrevious: {
                            if let idx = availableYears.firstIndex(of: effectiveYear), idx > 0 {
                                selectedYear = availableYears[idx - 1]
                            }
                        },
                        onNext: {
                            if let idx = availableYears.firstIndex(of: effectiveYear), idx < availableYears.count - 1 {
                                selectedYear = availableYears[idx + 1]
                            }
                        },
                        onPick: { year in selectedYear = year }
                    )

                    YearEndReviewContentView(
                        year: effectiveYear,
                        currencyCode: currencyCode,
                        onShowWrapped: { showingWrapped = true }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Year End Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack {
                TransactionFormView()
            }
        }
        .fullScreenCover(isPresented: $showingWrapped) {
            NavigationStack {
                YearEndWrappedView(
                    year: effectiveYear,
                    currencyCode: currencyCode
                )
            }
        }
        .onAppear {
            if let last = availableYears.last {
                selectedYear = last
            }
        }
    }
}

private struct YearEndHeaderCard: View {
    let year: Int
    let availableYears: [Int]
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(availableYears.first == year)
            .opacity(availableYears.first == year ? 0.35 : 1)

            Menu {
                ForEach(availableYears, id: \.self) { y in
                    Button(String(y)) { onPick(y) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Year End Review")
                        .font(.headline)
                    Text(String(year))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(availableYears.last == year)
            .opacity(availableYears.last == year ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct YearEndReviewContentView: View {
    let year: Int
    let currencyCode: String
    let onShowWrapped: () -> Void

    @Query private var yearTransactions: [Transaction]
    @Query private var previousYearTransactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var savingsGoals: [SavingsGoal]

    @AppStorage("retirement.isConfigured") private var retirementIsConfigured = false
    @AppStorage("retirement.includeInvestmentAccounts") private var includeInvestmentAccounts = true
    @AppStorage("retirement.includeSavingsAccounts") private var includeSavingsAccounts = false
    @AppStorage("retirement.includeOtherPositiveAccounts") private var includeOtherPositiveAccounts = false
    @AppStorage("retirement.externalAssets") private var externalAssetsText = ""
    @AppStorage("retirement.safeWithdrawalRate") private var safeWithdrawalRate = 0.04

    init(year: Int, currencyCode: String, onShowWrapped: @escaping () -> Void) {
        self.year = year
        self.currencyCode = currencyCode
        self.onShowWrapped = onShowWrapped

        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date()
        let prevStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? Date()
        let prevEnd = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()

        _yearTransactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= start && tx.date < end
            },
            sort: \Transaction.date,
            order: .forward
        )
        _previousYearTransactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= prevStart && tx.date < prevEnd
            },
            sort: \Transaction.date,
            order: .forward
        )
    }

    private var standardTransactions: [Transaction] {
        yearTransactions.filter { $0.kind == .standard }
    }

    private var incomeTransactions: [Transaction] {
        standardTransactions.filter { $0.amount > 0 && $0.category?.group?.type == .income }
    }

    private var expenseTransactions: [Transaction] {
        standardTransactions.filter { $0.amount < 0 }
    }

    private var transferTransactions: [Transaction] {
        yearTransactions.filter { $0.kind == .transfer }
    }

    private var totalIncome: Decimal {
        incomeTransactions.reduce(0) { $0 + $1.amount }
    }

    private var totalExpenses: Decimal {
        expenseTransactions.reduce(0) { $0 + abs($1.amount) }
    }

    private var netSavings: Decimal {
        totalIncome - totalExpenses
    }

    private var savingsRate: Double? {
        guard totalIncome > 0 else { return nil }
        return Double(truncating: (netSavings / totalIncome) as NSNumber)
    }

    private var topCategories: [YearEndGroupTotal] {
        var totals: [String: Decimal] = [:]
        for tx in expenseTransactions {
            let name = tx.category?.name ?? "Uncategorized"
            totals[name, default: 0] += abs(tx.amount)
        }
        return totals
            .map { YearEndGroupTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var topMerchants: [YearEndGroupTotal] {
        var totals: [String: Decimal] = [:]
        for tx in expenseTransactions {
            let trimmed = tx.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Unknown" : trimmed
            totals[name, default: 0] += abs(tx.amount)
        }
        return totals
            .map { YearEndGroupTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var biggestExpense: Transaction? {
        expenseTransactions.min(by: { $0.amount < $1.amount })
    }

    private var biggestIncome: Transaction? {
        incomeTransactions.max(by: { $0.amount < $1.amount })
    }

    private var monthlySummaries: [YearEndMonthlySummary] {
        let calendar = Calendar.current
        let monthStarts: [Date] = (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
        var bucket: [Date: (income: Decimal, expenses: Decimal)] = Dictionary(
            uniqueKeysWithValues: monthStarts.map { ($0, (income: 0, expenses: 0)) }
        )

        for tx in yearTransactions where tx.kind == .standard {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            var current = bucket[monthStart, default: (0, 0)]
            if tx.amount > 0, tx.category?.group?.type == .income {
                current.income += tx.amount
            } else if tx.amount < 0 {
                current.expenses += abs(tx.amount)
            }
            bucket[monthStart] = current
        }

        return monthStarts.map { monthStart in
            let value = bucket[monthStart] ?? (income: 0, expenses: 0)
            return YearEndMonthlySummary(monthStart: monthStart, income: value.income, expenses: value.expenses)
        }
    }

    private var bestMonth: YearEndMonthlySummary? {
        activeMonthlySummaries.max(by: { $0.net < $1.net })
    }

    private var worstMonth: YearEndMonthlySummary? {
        activeMonthlySummaries.min(by: { $0.net < $1.net })
    }

    private var activeMonthlySummaries: [YearEndMonthlySummary] {
        monthlySummaries.filter { $0.income != 0 || $0.expenses != 0 }
    }

    private var previousYearExpenseTotal: Decimal {
        let standard = previousYearTransactions.filter { $0.kind == .standard && $0.amount < 0 }
        return standard.reduce(0) { $0 + abs($1.amount) }
    }

    private var expenseYoYDelta: Double? {
        guard previousYearExpenseTotal > 0 else { return nil }
        let delta = (totalExpenses - previousYearExpenseTotal) / previousYearExpenseTotal
        return Double(truncating: delta as NSNumber)
    }

    private var topCategory: YearEndGroupTotal? { topCategories.first }
    private var topMerchant: YearEndGroupTotal? { topMerchants.first }

    private var monthStarts: [Date] {
        monthlySummaries.map(\.monthStart)
    }

    private var expenseTotalsByCategoryThisYear: [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for tx in expenseTransactions {
            let name = tx.category?.name ?? "Uncategorized"
            totals[name, default: 0] += abs(tx.amount)
        }
        return totals
    }

    private var expenseTotalsByCategoryPreviousYear: [String: Decimal] {
        let standard = previousYearTransactions.filter { $0.kind == .standard && $0.amount < 0 }
        var totals: [String: Decimal] = [:]
        for tx in standard {
            let name = tx.category?.name ?? "Uncategorized"
            totals[name, default: 0] += abs(tx.amount)
        }
        return totals
    }

    private var categoryYoYDeltaItems: [YearEndDeltaItem] {
        let keys = Set(expenseTotalsByCategoryThisYear.keys).union(expenseTotalsByCategoryPreviousYear.keys)
        return keys.map { name in
            let thisTotal = expenseTotalsByCategoryThisYear[name] ?? 0
            let prevTotal = expenseTotalsByCategoryPreviousYear[name] ?? 0
            return YearEndDeltaItem(
                name: name,
                thisTotal: thisTotal,
                previousTotal: prevTotal
            )
        }
        .sorted { $0.delta > $1.delta }
    }

    private var topCategoryDeltaIncreases: [YearEndDeltaItem] {
        Array(categoryYoYDeltaItems.filter { $0.delta > 0 }.prefix(6))
    }

    private var topCategoryDeltaDecreases: [YearEndDeltaItem] {
        Array(categoryYoYDeltaItems.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(6))
    }

    private var expenseByMonthByCategory: [Date: [String: Decimal]] {
        let calendar = Calendar.current
        var bucket: [Date: [String: Decimal]] = Dictionary(uniqueKeysWithValues: monthStarts.map { ($0, [:]) })

        for tx in expenseTransactions {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            let name = tx.category?.name ?? "Uncategorized"
            bucket[monthStart, default: [:]][name, default: 0] += abs(tx.amount)
        }
        return bucket
    }

    private var incomeByMonthBySource: [Date: [String: Decimal]] {
        let calendar = Calendar.current
        var bucket: [Date: [String: Decimal]] = Dictionary(uniqueKeysWithValues: monthStarts.map { ($0, [:]) })

        for tx in incomeTransactions {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            let name = tx.category?.name ?? "Income"
            bucket[monthStart, default: [:]][name, default: 0] += tx.amount
        }
        return bucket
    }

    private var topExpenseCategoryNamesForStack: [String] {
        Array(topCategories.prefix(7)).map(\.name)
    }

    private var topIncomeSourceNamesForStack: [String] {
        let totals: [String: Decimal] = incomeTransactions.reduce(into: [:]) { partial, tx in
            let name = tx.category?.name ?? "Income"
            partial[name, default: 0] += tx.amount
        }
        return totals
            .sorted { $0.value > $1.value }
            .map(\.key)
            .prefix(6)
            .map { $0 }
    }

    private var spendingStackedPoints: [YearEndStackedPoint] {
        let keep = Set(topExpenseCategoryNamesForStack)
        var points: [YearEndStackedPoint] = []

        for monthStart in monthStarts {
            let monthTotals = expenseByMonthByCategory[monthStart] ?? [:]
            let other = monthTotals.reduce(0) { partial, kv in
                keep.contains(kv.key) ? partial : partial + kv.value
            }

            for name in topExpenseCategoryNamesForStack {
                points.append(
                    YearEndStackedPoint(monthStart: monthStart, series: name, value: monthTotals[name] ?? 0)
                )
            }
            if other > 0 {
                points.append(
                    YearEndStackedPoint(monthStart: monthStart, series: "Other", value: other)
                )
            }
        }
        return points
    }

    private var incomeStackedPoints: [YearEndStackedPoint] {
        let keep = Set(topIncomeSourceNamesForStack)
        var points: [YearEndStackedPoint] = []

        for monthStart in monthStarts {
            let monthTotals = incomeByMonthBySource[monthStart] ?? [:]
            let other = monthTotals.reduce(0) { partial, kv in
                keep.contains(kv.key) ? partial : partial + kv.value
            }

            for name in topIncomeSourceNamesForStack {
                points.append(
                    YearEndStackedPoint(monthStart: monthStart, series: name, value: monthTotals[name] ?? 0)
                )
            }
            if other > 0 {
                points.append(
                    YearEndStackedPoint(monthStart: monthStart, series: "Other", value: other)
                )
            }
        }
        return points
    }

    private var spendingHeatmapPoints: [YearEndHeatmapPoint] {
        let calendar = Calendar.current
        var bucket: [String: Decimal] = [:]

        func weekdayIndexMondayFirst(from date: Date) -> Int {
            // Calendar weekday: 1=Sun ... 7=Sat
            let raw = calendar.component(.weekday, from: date)
            return (raw + 5) % 7 // Mon=0 ... Sun=6
        }

        for tx in expenseTransactions {
            let month = calendar.component(.month, from: tx.date)
            let weekday = weekdayIndexMondayFirst(from: tx.date)
            bucket["\(month)|\(weekday)", default: 0] += abs(tx.amount)
        }

        var points: [YearEndHeatmapPoint] = []
        for month in 1...12 {
            for weekday in 0...6 {
                let value = bucket["\(month)|\(weekday)"] ?? 0
                points.append(
                    YearEndHeatmapPoint(month: month, weekday: weekday, amount: value)
                )
            }
        }
        return points
    }

    private var merchantStats: [String: (total: Decimal, count: Int)] {
        var totals: [String: (total: Decimal, count: Int)] = [:]
        for tx in expenseTransactions {
            let trimmed = tx.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Unknown" : trimmed
            var current = totals[name, default: (0, 0)]
            current.total += abs(tx.amount)
            current.count += 1
            totals[name] = current
        }
        return totals
    }

    private var merchantParetoPoints: [YearEndParetoPoint] {
        let sorted = merchantStats.sorted { $0.value.total > $1.value.total }
        let total = sorted.reduce(Decimal(0)) { $0 + $1.value.total }
        guard total > 0 else { return [] }

        var running: Decimal = 0
        return Array(sorted.prefix(40).enumerated()).map { idx, element in
            running += element.value.total
            let share = Double(truncating: (running / total) as NSNumber)
            return YearEndParetoPoint(rank: idx + 1, cumulativeShare: share)
        }
    }

    private var merchantScatterPoints: [YearEndMerchantPoint] {
        merchantStats
            .sorted { $0.value.total > $1.value.total }
            .prefix(60)
            .map { name, value in
                YearEndMerchantPoint(
                    name: name,
                    count: value.count,
                    total: value.total
                )
            }
    }

    private var monthlySpendingValues: [Double] {
        monthlySummaries.map { YearEndChartFormat.toDouble($0.expenses) }
    }

    private var monthlySpendingMedian: Double? {
        YearEndChartFormat.median(monthlySpendingValues.filter { $0 > 0 })
    }

    private var monthlySpendingVolatility: Double? {
        YearEndChartFormat.coefficientOfVariation(monthlySpendingValues)
    }

    private var mostStableCategory: (name: String, volatility: Double)? {
        let candidates = Array(topCategories.prefix(10)).map(\.name)
        var best: (String, Double)? = nil

        for name in candidates {
            let values: [Double] = monthStarts.map { monthStart in
                YearEndChartFormat.toDouble(expenseByMonthByCategory[monthStart]?[name] ?? 0)
            }
            guard let cv = YearEndChartFormat.coefficientOfVariation(values),
                  values.reduce(0, +) > 0 else { continue }

            if best == nil || cv < (best?.1 ?? .infinity) {
                best = (name, cv)
            }
        }
        return best.map { (name: $0.0, volatility: $0.1) }
    }

    private var noSpendDays: Int? {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)),
              let dayCount = calendar.range(of: .day, in: .year, for: yearStart)?.count
        else { return nil }

        let activeDays: Set<Date> = Set(expenseTransactions.map { tx in
            calendar.startOfDay(for: tx.date)
        })
        let daysWithSpend = activeDays.filter { $0 >= yearStart && $0 < yearEnd }.count
        return max(0, dayCount - daysWithSpend)
    }

    private var biggestSpendingDay: (date: Date, amount: Decimal)? {
        let calendar = Calendar.current
        var bucket: [Date: Decimal] = [:]
        for tx in expenseTransactions {
            let day = calendar.startOfDay(for: tx.date)
            bucket[day, default: 0] += abs(tx.amount)
        }
        guard let best = bucket.max(by: { $0.value < $1.value }) else { return nil }
        return (date: best.key, amount: best.value)
    }

    private var mostCommonPurchaseBucket: Decimal? {
        let bucketSize: Double = 5
        var counts: [Int: Int] = [:]

        for tx in expenseTransactions {
            let v = abs(YearEndChartFormat.toDouble(tx.amount))
            guard v > 0 else { continue }
            let bucket = Int(floor(v / bucketSize))
            counts[bucket, default: 0] += 1
        }

        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return Decimal(Double(best) * bucketSize)
    }

    private var monthlyExpenseBudgetTotal: Decimal {
        categories
            .filter { $0.group?.type == .expense }
            .reduce(0) { $0 + max(0, $1.assigned) }
    }

    private var budgetAdherenceRate: Double? {
        guard monthlyExpenseBudgetTotal > 0 else { return nil }
        let under = monthlySummaries.filter { $0.expenses <= monthlyExpenseBudgetTotal }.count
        return Double(under) / Double(max(1, monthlySummaries.count))
    }

    private var biggestBudgetOverrun: YearEndBudgetOverrun? {
        guard monthlyExpenseBudgetTotal > 0 else { return nil }

        let assignedByCategory: [String: Decimal] = categories
            .filter { $0.group?.type == .expense }
            .reduce(into: [:]) { partial, category in
                partial[category.name] = max(0, category.assigned)
            }

        var best: YearEndBudgetOverrun? = nil
        for monthStart in monthStarts {
            let monthTotals = expenseByMonthByCategory[monthStart] ?? [:]
            for (name, spent) in monthTotals {
                let budget = assignedByCategory[name] ?? 0
                let overrun = spent - budget
                guard overrun > 0 else { continue }
                let candidate = YearEndBudgetOverrun(monthStart: monthStart, categoryName: name, overrun: overrun)
                if best == nil || candidate.overrun > (best?.overrun ?? 0) {
                    best = candidate
                }
            }
        }
        return best
    }

    private var savingsGoalsSummary: YearEndSavingsGoalsSummary {
        let totalSaved = savingsGoals.reduce(0) { $0 + $1.currentAmount }
        let totalTarget = savingsGoals.reduce(0) { $0 + $1.targetAmount }
        let achievedCount = savingsGoals.filter(\.isAchieved).count
        let dueThisYear = savingsGoals.filter { goal in
            guard let target = goal.targetDate else { return false }
            return Calendar.current.component(.year, from: target) == year
        }.count
        return YearEndSavingsGoalsSummary(
            totalGoals: savingsGoals.count,
            achievedGoals: achievedCount,
            dueThisYear: dueThisYear,
            totalSaved: totalSaved,
            totalTarget: totalTarget
        )
    }

    private var retirementSummary: YearEndRetirementSummary? {
        guard retirementIsConfigured else { return nil }
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }

        let includedAccounts = accounts.filter { account in
            if account.balance <= 0 { return false }
            switch account.type {
            case .investment:
                return includeInvestmentAccounts
            case .savings:
                return includeSavingsAccounts
            case .chequing, .creditCard, .lineOfCredit, .mortgage, .loans, .other:
                return includeOtherPositiveAccounts
            }
        }

        let includedAccountIDs = Set(includedAccounts.map(\.persistentModelID))
        let externalAssets = max(0, ImportParser.parseAmount(externalAssetsText) ?? 0)
        let currentPortfolio = includedAccounts.reduce(0) { $0 + max(0, $1.balance) } + externalAssets

        let transferPairs = Dictionary(grouping: yearTransactions.compactMap { tx -> Transaction? in
            guard tx.date >= start && tx.date < end else { return nil }
            guard tx.kind == .transfer else { return nil }
            guard tx.transferID != nil else { return nil }
            return tx
        }) { tx in
            tx.transferID ?? UUID()
        }

        var contributions: Decimal = 0

        for (_, legs) in transferPairs {
            guard legs.count >= 2 else { continue }
            let includedLegs = legs.filter { tx in
                guard let accountID = tx.account?.persistentModelID else { return false }
                return includedAccountIDs.contains(accountID)
            }

            guard let retirementLeg = includedLegs.first else { continue }
            guard retirementLeg.amount > 0 else { continue }

            let otherLeg = legs.first { $0.persistentModelID != retirementLeg.persistentModelID }
            let otherAccountID = otherLeg?.account?.persistentModelID
            let otherIsIncluded = otherAccountID.map { includedAccountIDs.contains($0) } ?? false
            guard !otherIsIncluded else { continue }

            contributions += retirementLeg.amount
        }

        for tx in yearTransactions {
            guard tx.date >= start && tx.date < end else { continue }
            guard tx.kind == .standard else { continue }
            guard tx.amount > 0 else { continue }
            guard let accountID = tx.account?.persistentModelID, includedAccountIDs.contains(accountID) else { continue }
            contributions += tx.amount
        }

        let annualSpending = totalExpenses
        let requiredPortfolio: Decimal = safeWithdrawalRate > 0 ? (annualSpending / Decimal(safeWithdrawalRate)) : 0
        let fundedFraction: Double? = requiredPortfolio > 0 ? min(1, NSDecimalNumber(decimal: currentPortfolio / requiredPortfolio).doubleValue) : nil

        return YearEndRetirementSummary(
            contributions: contributions,
            currentPortfolio: currentPortfolio,
            requiredPortfolio: requiredPortfolio,
            fundedFraction: fundedFraction
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            YearEndHeroCard(
                year: year,
                currencyCode: currencyCode,
                income: totalIncome,
                expenses: totalExpenses,
                net: netSavings,
                savingsRate: savingsRate,
                expenseYoYDelta: expenseYoYDelta,
                onShowWrapped: onShowWrapped
            )

            if #available(iOS 16.0, *) {
                YearEndCashflowChartCard(
                    summaries: monthlySummaries,
                    currencyCode: currencyCode
                )

                YearEndTopCategoriesChartCard(
                    categories: Array(topCategories.prefix(6)),
                    currencyCode: currencyCode
                )

                YearEndSpendingByMonthChartCard(
                    points: spendingStackedPoints,
                    currencyCode: currencyCode
                )

                YearEndIncomeByMonthChartCard(
                    points: incomeStackedPoints,
                    currencyCode: currencyCode
                )

                YearEndSpendingHeatmapCard(
                    year: year,
                    points: spendingHeatmapPoints,
                    currencyCode: currencyCode
                )

                YearEndCategoryYoYDeltaChartCard(
                    increases: topCategoryDeltaIncreases,
                    decreases: topCategoryDeltaDecreases,
                    currencyCode: currencyCode
                )

                YearEndMerchantInsightsCard(
                    pareto: merchantParetoPoints,
                    scatter: merchantScatterPoints,
                    currencyCode: currencyCode
                )

                YearEndBehaviorMetricsCard(
                    currencyCode: currencyCode,
                    monthlySpendingMedian: monthlySpendingMedian,
                    monthlySpendingVolatility: monthlySpendingVolatility,
                    mostStableCategory: mostStableCategory,
                    noSpendDays: noSpendDays,
                    biggestSpendingDay: biggestSpendingDay,
                    mostCommonPurchaseBucket: mostCommonPurchaseBucket,
                    budgetAdherenceRate: budgetAdherenceRate,
                    biggestBudgetOverrun: biggestBudgetOverrun
                )

                YearEndSavingsGoalsCard(
                    summary: savingsGoalsSummary,
                    goals: Array(savingsGoals.prefix(6)),
                    currencyCode: currencyCode
                )

                if let retirementSummary {
                    YearEndRetirementCard(
                        summary: retirementSummary,
                        currencyCode: currencyCode
                    )
                }
            }

            HStack(spacing: 12) {
                MetricCard(
                    title: "Top Category",
                    value: topCategory?.name ?? "—",
                    subtitle: topCategory.map { $0.total.formatted(.currency(code: currencyCode)) } ?? "No expenses",
                    systemImage: "chart.pie.fill",
                    tint: .orange
                )
                MetricCard(
                    title: "Top Merchant",
                    value: topMerchant?.name ?? "—",
                    subtitle: topMerchant.map { $0.total.formatted(.currency(code: currencyCode)) } ?? "No expenses",
                    systemImage: "building.2.fill",
                    tint: .indigo
                )
            }

            HStack(spacing: 12) {
                MetricCard(
                    title: "Biggest Expense",
                    value: biggestExpense?.payee.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrDash ?? "—",
                    subtitle: biggestExpense.map { abs($0.amount).formatted(.currency(code: currencyCode)) } ?? "No expenses",
                    systemImage: "arrow.up.right.circle.fill",
                    tint: .red
                )
                MetricCard(
                    title: "Biggest Income",
                    value: biggestIncome?.payee.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrDash ?? "—",
                    subtitle: biggestIncome.map { $0.amount.formatted(.currency(code: currencyCode)) } ?? "No income",
                    systemImage: "arrow.down.left.circle.fill",
                    tint: .green
                )
            }

            if activeMonthlySummaries.count >= 2, let bestMonth, let worstMonth {
                YearEndMonthHighlightsCard(
                    best: bestMonth,
                    worst: worstMonth,
                    currencyCode: currencyCode
                )
            }

            YearEndTopListCard(
                title: "Top Spending Categories",
                subtitle: "Where your money went",
                items: Array(topCategories.prefix(8)),
                currencyCode: currencyCode,
                systemImage: "list.bullet.rectangle.portrait",
                emptyMessage: "No expenses recorded for this year."
            )

            YearEndTopListCard(
                title: "Top Merchants",
                subtitle: "Who you paid most often",
                items: Array(topMerchants.prefix(8)),
                currencyCode: currencyCode,
                systemImage: "cart.fill",
                emptyMessage: "No expenses recorded for this year."
            )

            YearEndTransfersCard(
                transfersCount: transferTransactions.count,
                pairedTransfersCount: Set(transferTransactions.compactMap(\.transferID)).count,
                currencyCode: currencyCode,
                totalTransferVolume: transferTransactions.reduce(0) { $0 + abs($1.amount) }
            )
        }
    }
}

@available(iOS 16.0, *)
private struct YearEndCashflowChartCard: View {
    let summaries: [YearEndMonthlySummary]
    let currencyCode: String

    private enum Series: String {
        case income = "Income"
        case spent = "Spent"
    }

    private struct BarPoint: Identifiable {
        let monthStart: Date
        let series: Series
        let value: Double
        var id: String { "\(monthStart.timeIntervalSince1970)-\(series.rawValue)" }
    }

    private var hasAnyData: Bool {
        summaries.contains { $0.income != 0 || $0.expenses != 0 }
    }

    private var barPoints: [BarPoint] {
        summaries.flatMap { summary in
            [
                BarPoint(
                    monthStart: summary.monthStart,
                    series: .income,
                    value: YearEndChartFormat.toDouble(summary.income)
                ),
                BarPoint(
                    monthStart: summary.monthStart,
                    series: .spent,
                    value: YearEndChartFormat.toDouble(summary.expenses)
                ),
            ]
        }
    }

    private var yDomain: ClosedRange<Double> {
        let incomes = summaries.map { YearEndChartFormat.toDouble($0.income) }
        let expenses = summaries.map { YearEndChartFormat.toDouble($0.expenses) }
        let netValues = summaries.map { YearEndChartFormat.toDouble($0.net) }

        let minValue = min(netValues.min() ?? 0, 0)
        let maxValue = max((incomes + expenses + netValues).max() ?? 0, 0)
        let span = max(1, maxValue - minValue)
        let padding = span * 0.12
        return (minValue - padding)...(maxValue + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Cash Flow")
                        .font(.headline)
                    Text("Income vs spending, month by month.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                legendDot(color: .green, title: "Income")
                legendDot(color: .red, title: "Spent")
                legendDot(color: .blue, title: "Net")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !hasAnyData {
                Text("No income or expense activity recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart {
                    ForEach(barPoints) { point in
                        BarMark(
                            x: .value("Month", point.monthStart, unit: .month),
                            y: .value("Amount", point.value)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Series", point.series.rawValue))
                        .position(by: .value("Series", point.series.rawValue))
                    }

                    ForEach(summaries) { summary in
                        LineMark(
                            x: .value("Month", summary.monthStart, unit: .month),
                            y: .value("Net", YearEndChartFormat.toDouble(summary.net))
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("Month", summary.monthStart, unit: .month),
                            y: .value("Net", YearEndChartFormat.toDouble(summary.net))
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(20)
                    }

                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.primary.opacity(0.12))
                }
                .chartForegroundStyleScale([
                    Series.income.rawValue: Color.green,
                    Series.spent.rawValue: Color.red,
                ])
                .chartLegend(.hidden)
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: summaries.map(\.monthStart)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(y, currencyCode: currencyCode))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .lineLimit(1)
        }
    }
}

@available(iOS 16.0, *)
private struct YearEndTopCategoriesChartCard: View {
    let categories: [YearEndGroupTotal]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Categories (Chart)")
                        .font(.headline)
                    Text("Your biggest spending buckets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.secondary)
            }

            if categories.isEmpty {
                Text("No expenses recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(categories) { item in
                    BarMark(
                        x: .value("Spent", YearEndChartFormat.toDouble(item.total)),
                        y: .value("Category", item.name)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(Color.orange.gradient)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let x = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(x, currencyCode: currencyCode))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.03))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
private struct YearEndSpendingByMonthChartCard: View {
    let points: [YearEndStackedPoint]
    let currencyCode: String

    private var hasData: Bool { points.contains { $0.value != 0 } }

    private struct Segment: Identifiable {
        let monthStart: Date
        let series: String
        let y0: Double
        let y1: Double
        var id: String { "\(monthStart.timeIntervalSince1970)-\(series)-\(y0)" }
    }

    private var seriesOrder: [String] {
        var totals: [String: Double] = [:]
        for point in points {
            totals[point.series, default: 0] += YearEndChartFormat.toDouble(point.value)
        }
        return totals
            .sorted { a, b in
                if a.key == "Other" { return false }
                if b.key == "Other" { return true }
                return a.value > b.value
            }
            .map(\.key)
    }

    private var segments: [Segment] {
        let grouped = Dictionary(grouping: points, by: \.monthStart)
        var result: [Segment] = []

        for (monthStart, monthPoints) in grouped {
            let bySeries: [String: Double] = monthPoints.reduce(into: [:]) { partial, point in
                partial[point.series, default: 0] += YearEndChartFormat.toDouble(point.value)
            }
            var running: Double = 0
            for series in seriesOrder {
                let v = bySeries[series] ?? 0
                guard v > 0 else { continue }
                result.append(Segment(monthStart: monthStart, series: series, y0: running, y1: running + v))
                running += v
            }
        }

        return result.sorted {
            if $0.monthStart != $1.monthStart { return $0.monthStart < $1.monthStart }
            return $0.y0 < $1.y0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spending By Month")
                        .font(.headline)
                    Text("Which categories drove each month.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                Text("No expenses recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(segments) { segment in
                    BarMark(
                        x: .value("Month", segment.monthStart, unit: .month),
                        yStart: .value("Start", segment.y0),
                        yEnd: .value("End", segment.y1)
                    )
                    .foregroundStyle(by: .value("Category", segment.series))
                    .cornerRadius(3)
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(y, currencyCode: currencyCode))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
private struct YearEndIncomeByMonthChartCard: View {
    let points: [YearEndStackedPoint]
    let currencyCode: String

    private var hasData: Bool { points.contains { $0.value != 0 } }

    private struct Segment: Identifiable {
        let monthStart: Date
        let series: String
        let y0: Double
        let y1: Double
        var id: String { "\(monthStart.timeIntervalSince1970)-\(series)-\(y0)" }
    }

    private var seriesOrder: [String] {
        var totals: [String: Double] = [:]
        for point in points {
            totals[point.series, default: 0] += YearEndChartFormat.toDouble(point.value)
        }
        return totals
            .sorted { a, b in
                if a.key == "Other" { return false }
                if b.key == "Other" { return true }
                return a.value > b.value
            }
            .map(\.key)
    }

    private var segments: [Segment] {
        let grouped = Dictionary(grouping: points, by: \.monthStart)
        var result: [Segment] = []

        for (monthStart, monthPoints) in grouped {
            let bySeries: [String: Double] = monthPoints.reduce(into: [:]) { partial, point in
                partial[point.series, default: 0] += YearEndChartFormat.toDouble(point.value)
            }
            var running: Double = 0
            for series in seriesOrder {
                let v = bySeries[series] ?? 0
                guard v > 0 else { continue }
                result.append(Segment(monthStart: monthStart, series: series, y0: running, y1: running + v))
                running += v
            }
        }

        return result.sorted {
            if $0.monthStart != $1.monthStart { return $0.monthStart < $1.monthStart }
            return $0.y0 < $1.y0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Income Sources By Month")
                        .font(.headline)
                    Text("Where your income came from.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                Text("No income recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(segments) { segment in
                    BarMark(
                        x: .value("Month", segment.monthStart, unit: .month),
                        yStart: .value("Start", segment.y0),
                        yEnd: .value("End", segment.y1)
                    )
                    .foregroundStyle(by: .value("Source", segment.series))
                    .cornerRadius(3)
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(y, currencyCode: currencyCode))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
private struct YearEndSpendingHeatmapCard: View {
    let year: Int
    let points: [YearEndHeatmapPoint]
    let currencyCode: String

    private var hasData: Bool { points.contains { $0.amount != 0 } }

    private var weekdayLabels: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Reorder to Monday-first
        return Array(symbols[1...6]) + [symbols[0]]
    }

    private var monthLabels: [String] {
        let calendar = Calendar.current
        let base = calendar.shortStandaloneMonthSymbols
        return Array(base.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spending Pattern Heatmap")
                        .font(.headline)
                    Text("When you tend to spend (weekday × month).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                Text("No expenses recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(points) { point in
                    RectangleMark(
                        x: .value("Weekday", weekdayLabels[point.weekday]),
                        y: .value("Month", monthLabels[point.month - 1])
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Spent", YearEndChartFormat.toDouble(point.amount)))
                }
                .chartForegroundStyleScale(range: Gradient(colors: [Color(.systemGray5), .orange, .red]))
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: weekdayLabels) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.03))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: monthLabels) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.03))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 280)

                Text("Lower → Higher")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
private struct YearEndCategoryYoYDeltaChartCard: View {
    let increases: [YearEndDeltaItem]
    let decreases: [YearEndDeltaItem]
    let currencyCode: String

    private var hasData: Bool {
        !increases.isEmpty || !decreases.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Category Changes vs Last Year")
                        .font(.headline)
                    Text("Biggest increases and decreases in spending.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.and.down.circle")
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                Text("Not enough year-over-year data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 12) {
                    deltaList(title: "Up", items: increases, tint: .red)
                    deltaList(title: "Down", items: decreases.map { $0.asPositiveDelta }, tint: .green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func deltaList(title: String, items: [YearEndDeltaItem], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("Delta", YearEndChartFormat.toDouble(item.delta)),
                        y: .value("Category", item.name)
                    )
                    .foregroundStyle(tint.gradient)
                    .cornerRadius(6)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let x = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(x, currencyCode: currencyCode))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.03))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
private struct YearEndMerchantInsightsCard: View {
    let pareto: [YearEndParetoPoint]
    let scatter: [YearEndMerchantPoint]
    let currencyCode: String

    private var hasData: Bool { !pareto.isEmpty || !scatter.isEmpty }

    private var pareto80Point: YearEndParetoPoint? {
        pareto.first { $0.cumulativeShare >= 0.8 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !hasData {
                Text("No merchant data recorded for this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                paretoSection
                scatterSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Merchant Insights")
                    .font(.headline)
                Text("How concentrated your spending is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "building.2.crop.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var paretoSection: some View {
        if !pareto.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pareto Curve")
                    .font(.subheadline.weight(.semibold))

                Chart {
                    ForEach(pareto) { point in
                        LineMark(
                            x: .value("Rank", point.rank),
                            y: .value("Cumulative", point.cumulativeShare)
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("Rank", point.rank),
                            y: .value("Cumulative", point.cumulativeShare)
                        )
                        .foregroundStyle(Color.blue.opacity(0.5))
                        .symbolSize(14)
                    }

                    RuleMark(y: .value("80%", 0.8))
                        .foregroundStyle(Color.primary.opacity(0.12))

                    if let p80 = pareto80Point {
                        RuleMark(x: .value("Rank 80%", p80.rank))
                            .foregroundStyle(Color.orange.opacity(0.5))
                            .annotation(position: .top, alignment: .leading) {
                                Text("80% by top \(p80.rank)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            }
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let x = value.as(Int.self) {
                            Text("\(x)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let y = value.as(Double.self) {
                            Text(y.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var scatterSection: some View {
        if !scatter.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Frequency vs Spend")
                    .font(.subheadline.weight(.semibold))

                Chart(scatter) { point in
                    PointMark(
                        x: .value("Transactions", point.count),
                        y: .value("Total", YearEndChartFormat.toDouble(point.total))
                    )
                    .foregroundStyle(Color.purple.opacity(0.65))
                    .symbolSize(YearEndChartFormat.scatterSymbolSize(for: YearEndChartFormat.toDouble(point.total)))
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let x = value.as(Int.self) {
                                Text("\(x)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(YearEndChartFormat.compactCurrency(y, currencyCode: currencyCode))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct YearEndBehaviorMetricsCard: View {
    let currencyCode: String
    let monthlySpendingMedian: Double?
    let monthlySpendingVolatility: Double?
    let mostStableCategory: (name: String, volatility: Double)?
    let noSpendDays: Int?
    let biggestSpendingDay: (date: Date, amount: Decimal)?
    let mostCommonPurchaseBucket: Decimal?
    let budgetAdherenceRate: Double?
    let biggestBudgetOverrun: YearEndBudgetOverrun?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Money Habits")
                        .font(.headline)
                    Text("A few fun metrics and quick wins.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                metricRow(
                    title: "Median monthly spending",
                    value: monthlySpendingMedian.map { YearEndChartFormat.compactCurrency($0, currencyCode: currencyCode) } ?? "—"
                )
                metricRow(
                    title: "Spending volatility",
                    value: monthlySpendingVolatility.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
                )
                metricRow(
                    title: "Most stable category",
                    value: mostStableCategory.map { "\($0.name) · \($0.volatility.formatted(.percent.precision(.fractionLength(0))))" } ?? "—"
                )
                metricRow(
                    title: "No-spend days",
                    value: noSpendDays.map(String.init) ?? "—"
                )
                metricRow(
                    title: "Biggest spending day",
                    value: biggestSpendingDay.map { "\($0.date.formatted(.dateTime.month(.abbreviated).day())) · \($0.amount.formatted(.currency(code: currencyCode)))" } ?? "—"
                )
                metricRow(
                    title: "Most common purchase",
                    value: mostCommonPurchaseBucket.map { $0.formatted(.currency(code: currencyCode)) } ?? "—"
                )

                if let budgetAdherenceRate {
                    metricRow(
                        title: "Budget adherence",
                        value: budgetAdherenceRate.formatted(.percent.precision(.fractionLength(0)))
                    )
                }

                if let biggestBudgetOverrun {
                    metricRow(
                        title: "Biggest budget overrun",
                        value: "\(biggestBudgetOverrun.categoryName) · \(biggestBudgetOverrun.overrun.formatted(.currency(code: currencyCode)))"
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

@available(iOS 16.0, *)
private struct YearEndSavingsGoalsCard: View {
    let summary: YearEndSavingsGoalsSummary
    let goals: [SavingsGoal]
    let currencyCode: String

    private var progress: Double {
        guard summary.totalTarget > 0 else { return 0 }
        return Double(truncating: (summary.totalSaved / summary.totalTarget) as NSNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Savings Goals")
                        .font(.headline)
                    Text("Progress snapshot across your goals.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "target")
                    .foregroundStyle(.secondary)
            }

            HStack {
                stat(title: "Goals", value: "\(summary.totalGoals)")
                Spacer()
                stat(title: "Achieved", value: "\(summary.achievedGoals)")
                Spacer()
                if summary.dueThisYear > 0 {
                    stat(title: "Due this year", value: "\(summary.dueThisYear)")
                } else {
                    stat(title: "Due this year", value: "—")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.totalSaved.formatted(.currency(code: currencyCode)))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                ProgressView(value: progress)
                    .tint(.green)
            }

            if !goals.isEmpty {
                Chart(goals) { goal in
                    BarMark(
                        x: .value("Progress", goal.progressPercentage),
                        y: .value("Goal", goal.name)
                    )
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(6)
                }
                .chartXScale(domain: 0...100)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let x = value.as(Double.self) {
                                Text("\(Int(x))%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.03))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct YearEndRetirementCard: View {
    let summary: YearEndRetirementSummary
    let currencyCode: String

    private var fundedText: String {
        guard let fraction = summary.fundedFraction else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retirement Snapshot")
                        .font(.headline)
                    Text("Based on your retirement plan settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.secondary)
            }

            HStack {
                stat(title: "Contributions", value: summary.contributions.formatted(.currency(code: currencyCode)))
                Spacer()
                stat(title: "Portfolio", value: summary.currentPortfolio.formatted(.currency(code: currencyCode)))
            }

            HStack {
                stat(title: "Target", value: summary.requiredPortfolio > 0 ? summary.requiredPortfolio.formatted(.currency(code: currencyCode)) : "—")
                Spacer()
                stat(title: "Funded", value: fundedText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private enum YearEndChartFormat {
    static func toDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func compactCurrency(_ value: Double, currencyCode: String) -> String {
        let symbol = currencySymbol(for: currencyCode)
        let sign = value < 0 ? "−" : ""
        let absValue = abs(value)

        let scaled: Double
        let suffix: String
        switch absValue {
        case 1_000_000_000...:
            scaled = absValue / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = absValue / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = absValue / 1_000
            suffix = "K"
        default:
            scaled = absValue
            suffix = ""
        }

        let fractionDigits: Int
        if suffix.isEmpty {
            fractionDigits = 0
        } else if scaled < 10 {
            fractionDigits = 1
        } else {
            fractionDigits = 0
        }

        let number = scaled.formatted(.number.precision(.fractionLength(fractionDigits)))
        return "\(sign)\(symbol)\(number)\(suffix)"
    }

    private static func currencySymbol(for currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.current
        let symbol = formatter.currencySymbol ?? currencyCode
        return symbol
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count % 2 == 1 {
            return sorted[sorted.count / 2]
        }
        let a = sorted[(sorted.count / 2) - 1]
        let b = sorted[sorted.count / 2]
        return (a + b) / 2
    }

    static func coefficientOfVariation(_ values: [Double]) -> Double? {
        let filtered = values.filter { $0 != 0 }
        guard filtered.count >= 2 else { return nil }
        let mean = filtered.reduce(0, +) / Double(filtered.count)
        guard mean != 0 else { return nil }
        let variance = filtered.reduce(0) { $0 + pow($1 - mean, 2) } / Double(filtered.count)
        let stddev = sqrt(variance)
        return stddev / abs(mean)
    }

    static func scatterSymbolSize(for total: Double) -> Double {
        // Keep dots visible but not overwhelming.
        let clamped = max(0, min(total, 50_000))
        return 20 + sqrt(clamped) * 0.35
    }
}

private struct YearEndHeroCard: View {
    let year: Int
    let currencyCode: String
    let income: Decimal
    let expenses: Decimal
    let net: Decimal
    let savingsRate: Double?
    let expenseYoYDelta: Double?
    let onShowWrapped: () -> Void

    private var netLabel: String {
        if net >= 0 {
            return "Saved"
        }
        return "Overspent"
    }

    private var netValue: String {
        abs(net).formatted(.currency(code: currencyCode))
    }

    private var savingsRateText: String {
        guard let savingsRate else { return "—" }
        return (savingsRate).formatted(.percent.precision(.fractionLength(0)))
    }

    private var yoyText: String? {
        guard let expenseYoYDelta else { return nil }
        let sign = expenseYoYDelta >= 0 ? "+" : "−"
        let value = abs(expenseYoYDelta).formatted(.percent.precision(.fractionLength(0)))
        return "\(sign)\(value) spending vs last year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(year) Recap")
                        .font(.headline)
                    Text("A Spotify‑wrapped style summary of your money.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onShowWrapped()
                } label: {
                    Label("Wrapped", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(netLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(netValue)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Income")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(income.formatted(.currency(code: currencyCode)))
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Spent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(expenses.formatted(.currency(code: currencyCode)))
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "percent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Savings rate \(savingsRateText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if let yoyText {
                        Text(yoyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct YearEndMonthHighlightsCard: View {
    let best: YearEndMonthlySummary
    let worst: YearEndMonthlySummary
    let currencyCode: String

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    private func netLabel(_ value: Decimal) -> String {
        if value >= 0 { return "Saved" }
        return "Overspent"
    }

    private func netValue(_ value: Decimal) -> String {
        abs(value).formatted(.currency(code: currencyCode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month Highlights")
                .font(.headline)

            HStack(spacing: 12) {
                highlight(
                    title: "Best Month",
                    month: monthLabel(best.monthStart),
                    label: netLabel(best.net),
                    value: netValue(best.net),
                    systemImage: "crown.fill",
                    tint: .orange
                )

                highlight(
                    title: "Most Challenging",
                    month: monthLabel(worst.monthStart),
                    label: netLabel(worst.net),
                    value: netValue(worst.net),
                    systemImage: "chart.line.downtrend.xyaxis",
                    tint: .purple
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func highlight(title: String, month: String, label: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(month)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct YearEndTopListCard: View {
    let title: String
    let subtitle: String
    let items: [YearEndGroupTotal]
    let currencyCode: String
    let systemImage: String
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(item.total.formatted(.currency(code: currencyCode)))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct YearEndTransfersCard: View {
    let transfersCount: Int
    let pairedTransfersCount: Int
    let currencyCode: String
    let totalTransferVolume: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transfers")
                        .font(.headline)
                    Text("Internal movement isn’t counted as income or spending.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
            }

            HStack {
                stat(title: "Transfer transactions", value: "\(transfersCount)")
                Spacer()
                stat(title: "Linked pairs", value: "\(pairedTransfersCount)")
                Spacer()
                stat(title: "Total volume", value: totalTransferVolume.formatted(.currency(code: currencyCode)))
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

fileprivate struct YearEndGroupTotal: Identifiable {
    let name: String
    let total: Decimal
    var id: String { name }
}

fileprivate struct YearEndDeltaItem: Identifiable {
    let name: String
    let thisTotal: Decimal
    let previousTotal: Decimal
    var delta: Decimal { thisTotal - previousTotal }
    var id: String { name }

    var asPositiveDelta: YearEndDeltaItem {
        let magnitude = delta < 0 ? -delta : delta
        return YearEndDeltaItem(name: name, thisTotal: magnitude, previousTotal: 0)
    }
}

fileprivate struct YearEndStackedPoint: Identifiable {
    let monthStart: Date
    let series: String
    let value: Decimal
    var id: String { "\(monthStart.timeIntervalSince1970)-\(series)" }
}

fileprivate struct YearEndHeatmapPoint: Identifiable {
    let month: Int // 1...12
    let weekday: Int // Mon=0 ... Sun=6
    let amount: Decimal
    var id: String { "\(month)-\(weekday)" }
}

fileprivate struct YearEndParetoPoint: Identifiable {
    let rank: Int
    let cumulativeShare: Double
    var id: Int { rank }
}

fileprivate struct YearEndMerchantPoint: Identifiable {
    let name: String
    let count: Int
    let total: Decimal
    var id: String { name }
}

fileprivate struct YearEndBudgetOverrun: Identifiable {
    let monthStart: Date
    let categoryName: String
    let overrun: Decimal
    var id: String { "\(monthStart.timeIntervalSince1970)-\(categoryName)" }
}

fileprivate struct YearEndSavingsGoalsSummary {
    let totalGoals: Int
    let achievedGoals: Int
    let dueThisYear: Int
    let totalSaved: Decimal
    let totalTarget: Decimal
}

fileprivate struct YearEndRetirementSummary {
    let contributions: Decimal
    let currentPortfolio: Decimal
    let requiredPortfolio: Decimal
    let fundedFraction: Double?
}

fileprivate struct YearEndMonthlySummary: Identifiable {
    let monthStart: Date
    let income: Decimal
    let expenses: Decimal
    var net: Decimal { income - expenses }
    var id: Date { monthStart }
}

private struct YearEndWrappedView: View {
    let year: Int
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var isHeaderCompact = false

    var body: some View {
        YearEndReviewContentView(
            year: year,
            currencyCode: currencyCode,
            onShowWrapped: {}
        )
        .overlay {
            YearEndWrappedStoriesOverlay(
                year: year,
                currencyCode: currencyCode,
                page: $page,
                onDone: { dismiss() }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct YearEndWrappedStoriesOverlay: View {
    let year: Int
    let currencyCode: String
    @Binding var page: Int
    let onDone: () -> Void

    @Query private var yearTransactions: [Transaction]

    init(year: Int, currencyCode: String, page: Binding<Int>, onDone: @escaping () -> Void) {
        self.year = year
        self.currencyCode = currencyCode
        self._page = page
        self.onDone = onDone

        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date()
        _yearTransactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= start && tx.date < end
            },
            sort: \Transaction.date,
            order: .forward
        )
    }

    private var standardTransactions: [Transaction] {
        yearTransactions.filter { $0.kind == .standard }
    }

    private var incomeTransactions: [Transaction] {
        standardTransactions.filter { $0.amount > 0 && $0.category?.group?.type == .income }
    }

    private var expenseTransactions: [Transaction] {
        standardTransactions.filter { $0.amount < 0 }
    }

    private var totalIncome: Decimal {
        incomeTransactions.reduce(0) { $0 + $1.amount }
    }

    private var totalExpenses: Decimal {
        expenseTransactions.reduce(0) { $0 + abs($1.amount) }
    }

    private var net: Decimal { totalIncome - totalExpenses }

    private var topCategory: (name: String, total: Decimal)? {
        var totals: [String: Decimal] = [:]
        for tx in expenseTransactions {
            totals[tx.category?.name ?? "Uncategorized", default: 0] += abs(tx.amount)
        }
        return totals.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    private var topMerchant: (name: String, total: Decimal)? {
        var totals: [String: Decimal] = [:]
        for tx in expenseTransactions {
            let trimmed = tx.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            totals[trimmed.isEmpty ? "Unknown" : trimmed, default: 0] += abs(tx.amount)
        }
        return totals.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    private var biggestExpense: Transaction? {
        expenseTransactions.min(by: { $0.amount < $1.amount })
    }

    private var biggestIncome: Transaction? {
        incomeTransactions.max(by: { $0.amount < $1.amount })
    }

    private var stories: [WrappedStory] {
        var items: [WrappedStory] = []
        items.append(
            WrappedStory(
                title: "Escape Budget Wrapped",
                headline: String(year),
                caption: "Your year in money, in under a minute.",
                gradient: [.purple, .blue]
            )
        )
        items.append(
            WrappedStory(
                title: "You spent",
                headline: totalExpenses.formatted(.currency(code: currencyCode)),
                caption: "Total expenses (excluding transfers).",
                gradient: [.pink, .red]
            )
        )
        items.append(
            WrappedStory(
                title: net >= 0 ? "You saved" : "You overspent",
                headline: abs(net).formatted(.currency(code: currencyCode)),
                caption: "Income minus expenses for the year.",
                gradient: [.green, .teal]
            )
        )
        if let topCategory {
            items.append(
                WrappedStory(
                    title: "Top category",
                    headline: topCategory.name,
                    caption: topCategory.total.formatted(.currency(code: currencyCode)),
                    gradient: [.orange, .yellow]
                )
            )
        }
        if let topMerchant {
            items.append(
                WrappedStory(
                    title: "Top merchant",
                    headline: topMerchant.name,
                    caption: topMerchant.total.formatted(.currency(code: currencyCode)),
                    gradient: [.indigo, .cyan]
                )
            )
        }
        if let biggestExpense {
            items.append(
                WrappedStory(
                    title: "Biggest expense",
                    headline: biggestExpense.payee.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrDash ?? "—",
                    caption: abs(biggestExpense.amount).formatted(.currency(code: currencyCode)),
                    gradient: [.gray, .black]
                )
            )
        }
        if let biggestIncome {
            items.append(
                WrappedStory(
                    title: "Biggest income",
                    headline: biggestIncome.payee.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrDash ?? "—",
                    caption: biggestIncome.amount.formatted(.currency(code: currencyCode)),
                    gradient: [.mint, .blue]
                )
            )
        }
        items.append(
            WrappedStory(
                title: "That’s a wrap",
                headline: "Nice work",
                caption: "Keep going—small wins compound.",
                gradient: [.blue, .purple]
            )
        )
        return items
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                    YearEndWrappedStoryCard(story: story)
                        .tag(index)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .navigationTitle("Wrapped")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDone() }
            }
        }
    }
}

private struct WrappedStory: Identifiable {
    let id = UUID()
    let title: String
    let headline: String
    let caption: String
    let gradient: [Color]
}

private struct YearEndWrappedStoryCard: View {
    let story: WrappedStory

    var body: some View {
        ZStack {
            LinearGradient(colors: story.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                Text(story.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(story.headline)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(story.caption)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 520)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
    }
}

private extension String {
    var nonEmptyOrDash: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
