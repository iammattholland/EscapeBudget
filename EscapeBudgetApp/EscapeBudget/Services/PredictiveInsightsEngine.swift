import Foundation
import SwiftData

/// Generates predictive insights and smart notifications based on transaction patterns
@MainActor
struct PredictiveInsightsEngine {
    let modelContext: ModelContext

    private struct ComparisonRange {
        let start: Date
        let endExclusive: Date
        let label: String
        let kind: Kind

        enum Kind {
            case month
            case year
            case rolling
        }
    }

    private func previousComparisonRange(for dateRange: (start: Date, end: Date), calendar: Calendar = .current) -> ComparisonRange {
        let start = dateRange.start
        let end = dateRange.end

        // Detect a full calendar month selection (e.g. month filter).
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let monthEndExclusive = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? end
        let monthEndInclusive = monthEndExclusive.addingTimeInterval(-1)
        let isFullMonth = calendar.isDate(start, inSameDayAs: monthStart) && abs(end.timeIntervalSince(monthEndInclusive)) < 2

        if isFullMonth {
            let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            return ComparisonRange(start: prevMonthStart, endExclusive: monthStart, label: "last month", kind: .month)
        }

        // Detect a full calendar year selection (e.g. year filter).
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: start)) ?? start
        let yearEndExclusive = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? end
        let yearEndInclusive = yearEndExclusive.addingTimeInterval(-1)
        let isFullYear = calendar.isDate(start, inSameDayAs: yearStart) && abs(end.timeIntervalSince(yearEndInclusive)) < 2

        if isFullYear {
            let prevYearStart = calendar.date(byAdding: .year, value: -1, to: yearStart) ?? yearStart
            return ComparisonRange(start: prevYearStart, endExclusive: yearStart, label: "last year", kind: .year)
        }

        // Fallback: compare against the immediately preceding range of the same duration.
        let duration = max(1, end.timeIntervalSince(start))
        let prevStart = start.addingTimeInterval(-duration)
        return ComparisonRange(start: prevStart, endExclusive: start, label: "previous period", kind: .rolling)
    }

    private func daysInclusive(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let delta = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, delta + 1)
    }

    private func roundedCurrency(_ amount: Decimal) -> Decimal {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .bankers)
        return rounded
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    private func amountLooksStable(_ amounts: [Decimal]) -> Bool {
        guard amounts.count >= 3 else { return true }
        let ns = amounts.map { NSDecimalNumber(decimal: $0) }
        let doubles = ns.map { abs($0.doubleValue) }.sorted()
        guard let med = median(doubles), med > 0 else { return false }
        let allowedAbsolute = max(5.0, med * 0.25)
        let inBand = doubles.filter { abs($0 - med) <= allowedAbsolute }.count
        return Double(inBand) / Double(doubles.count) >= 0.8
    }

    private func intervalsLookMonthly(_ intervalsInDays: [Double]) -> (isMonthly: Bool, medianDays: Int)? {
        guard intervalsInDays.count >= 1 else { return nil }
        let cleaned = intervalsInDays.filter { $0.isFinite && $0 > 0 }
        guard !cleaned.isEmpty else { return nil }

        let med = median(cleaned) ?? cleaned.reduce(0, +) / Double(cleaned.count)
        guard med >= 25, med <= 35 else { return (false, Int(med.rounded())) }

        if cleaned.count >= 2 {
            let band = cleaned.filter { abs($0 - med) <= 6 }.count
            let stableEnough = Double(band) / Double(cleaned.count) >= 0.75
            return (stableEnough, Int(med.rounded()))
        }

        return (true, Int(med.rounded()))
    }

    private func expenseOutflowTotal(transactions: [Transaction]) -> Decimal {
        var outflow: Decimal = 0
        var refunds: Decimal = 0
        for tx in transactions where tx.kind == .standard && tx.account?.isTrackingOnly != true {
            if tx.amount < 0 {
                outflow += abs(tx.amount)
            } else if tx.amount > 0, tx.category?.group?.type == .expense {
                refunds += tx.amount
            }
        }
        return max(0, outflow - refunds)
    }

    private func incomeTotal(transactions: [Transaction]) -> Decimal {
        transactions
            .filter { tx in
                tx.kind == .standard &&
                tx.account?.isTrackingOnly != true &&
                tx.amount > 0 &&
                tx.category?.group?.type == .income
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    struct Insight: Identifiable, Hashable {
        let id = UUID()
        let type: InsightType
        let title: String
        let description: String
        let why: String?
        let severity: Severity
        let actionable: Bool
        let relatedCategoryID: PersistentIdentifier?
        let relatedCategoryName: String?
        let relatedPayee: String?

        init(
            type: InsightType,
            title: String,
            description: String,
            why: String? = nil,
            severity: Severity,
            actionable: Bool,
            relatedCategoryID: PersistentIdentifier? = nil,
            relatedCategoryName: String? = nil,
            relatedPayee: String? = nil
        ) {
            self.type = type
            self.title = title
            self.description = description
            self.why = why
            self.severity = severity
            self.actionable = actionable
            self.relatedCategoryID = relatedCategoryID
            self.relatedCategoryName = relatedCategoryName
            self.relatedPayee = relatedPayee
        }

        enum InsightType {
            case recurringExpenseDetected
            case unusualSpending
            case budgetProjection
            case savingsOpportunity
            case upcomingBill
            case spendingTrend
            case incomeVariation
        }

        enum Severity {
            case info
            case warning
            case alert

            var icon: String {
                switch self {
                case .info: return "lightbulb.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .alert: return "exclamationmark.circle.fill"
                }
            }
        }
    }

    private func formattedShortDateRange(start: Date, endExclusive: Date, calendar: Calendar = .current) -> String {
        let endInclusive = endExclusive.addingTimeInterval(-1)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")

        let startText = formatter.string(from: start)
        let endText = formatter.string(from: endInclusive)
        if calendar.isDate(start, inSameDayAs: endInclusive) {
            return startText
        }
        return "\(startText)–\(endText)"
    }

    /// Generate insights for the current period
    func generateInsights(
        transactions: [Transaction],
        dateRange: (start: Date, end: Date),
        categories: [Category],
        currentIncome: Decimal,
        currentExpenses: Decimal,
        savingsRate: Double?,
        currencyCode: String
    ) -> [Insight] {
        var insights: [Insight] = []

        // 1. Detect recurring expenses
        insights.append(contentsOf: detectRecurringExpenses(transactions: transactions, dateRange: dateRange, currencyCode: currencyCode))

        // 2. Detect unusual spending patterns
        insights.append(contentsOf: detectUnusualSpending(transactions: transactions, dateRange: dateRange, currencyCode: currencyCode))

        // 3. Budget projection
        insights.append(contentsOf: projectBudgetHealth(
            categories: categories,
            transactions: transactions,
            dateRange: dateRange,
            currencyCode: currencyCode
        ))

        // 4. Identify savings opportunities
        insights.append(contentsOf: identifySavingsOpportunities(
            transactions: transactions,
            currentIncome: currentIncome,
            currentExpenses: currentExpenses,
            savingsRate: savingsRate,
            currencyCode: currencyCode
        ))

        // 5. Predict upcoming bills
        insights.append(contentsOf: predictUpcomingBills(transactions: transactions, currencyCode: currencyCode))

        // 6. Analyze spending trends
        insights.append(contentsOf: analyzeSpendingTrends(transactions: transactions, dateRange: dateRange, currencyCode: currencyCode))

        // 7. Income variation alerts
        insights.append(contentsOf: analyzeIncomeVariation(transactions: transactions, dateRange: dateRange, currencyCode: currencyCode))

        // Sort by severity (alerts first, then warnings, then info)
        return insights.sorted { lhs, rhs in
            let severityOrder: [Insight.Severity: Int] = [.alert: 0, .warning: 1, .info: 2]
            return (severityOrder[lhs.severity] ?? 3) < (severityOrder[rhs.severity] ?? 3)
        }
    }

    // MARK: - Recurring Expense Detection

    private func detectRecurringExpenses(transactions: [Transaction], dateRange: (Date, Date), currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        // Group transactions by normalized payee
        let expenses = transactions.filter { $0.amount < 0 && $0.kind == .standard && $0.account?.isTrackingOnly != true }
        let grouped = Dictionary(grouping: expenses) { transaction in
            PayeeNormalizer.normalizeForComparison(transaction.payee)
        }

        for (payee, txs) in grouped where txs.count >= 2 {
            // Check if transactions occur at regular intervals
            let sortedTxs = txs.sorted { $0.date < $1.date }
            let sortedDates = sortedTxs.map(\.date)
            if sortedDates.count >= 2 {
                let intervalsDays = zip(sortedDates, sortedDates.dropFirst()).map { pair in
                    pair.1.timeIntervalSince(pair.0) / (24 * 3600)
                }
                guard let monthlyCheck = intervalsLookMonthly(intervalsDays) else { continue }

                // If average interval is roughly monthly (25-35 days), it's likely recurring
                if monthlyCheck.isMonthly {
                    // Avoid tagging wildly varying amounts as "recurring".
                    let amounts = sortedTxs.map(\.amount)
                    guard amountLooksStable(amounts) else { continue }

                    let avgAmount = txs.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(txs.count)
                    let displayPayee = txs.first?.payee ?? payee
                    let avgDays = monthlyCheck.medianDays

                    insights.append(Insight(
                        type: .recurringExpenseDetected,
                        title: "\(displayPayee) is recurring",
                        description: "About \(avgAmount.formatted(.currency(code: currencyCode))) monthly.",
                        why: "Based on \(txs.count) payments about every \(avgDays) days.",
                        severity: .info,
                        actionable: true,
                        relatedPayee: displayPayee
                    ))
                }
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Unusual Spending Detection

    private func detectUnusualSpending(transactions: [Transaction], dateRange: (Date, Date), currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        // Get historical average spending per category
        let currentStandard = transactions.filter { $0.kind == .standard && $0.account?.isTrackingOnly != true }
        struct CategoryBucket: Hashable {
            let id: PersistentIdentifier?
            let name: String

            func hash(into hasher: inout Hasher) {
                hasher.combine(name.lowercased())
            }

            static func == (lhs: CategoryBucket, rhs: CategoryBucket) -> Bool {
                lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame
            }
        }

        var categoryNet: [CategoryBucket: Decimal] = [:]
        categoryNet.reserveCapacity(16)
        for tx in currentStandard where tx.amount != 0 {
            let bucket = CategoryBucket(
                id: tx.category?.persistentModelID,
                name: tx.category?.name ?? "Uncategorized"
            )
            // Treat refunds (positive amounts with expense categories) as reducing category spend.
            if tx.amount > 0, tx.category?.group?.type != .expense { continue }
            categoryNet[bucket, default: 0] += tx.amount
        }

        // Fetch historical data (3 full months before current period; aligns to calendar months).
        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let rangeMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: rangeStart)) ?? rangeStart
        let historicalStart = calendar.date(byAdding: .month, value: -3, to: rangeMonthStart) ?? rangeMonthStart
        let historicalEnd = rangeMonthStart

        let standardRaw = TransactionKind.standard.rawValue
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.date >= historicalStart &&
            tx.date < historicalEnd &&
            tx.kindRawValue == standardRaw
        }

        guard let rawHistoricalTxs = try? modelContext.fetch(descriptor) else { return insights }
        let historicalTxs = rawHistoricalTxs.filter { $0.account?.isTrackingOnly != true }

        var historicalCategoryNet: [CategoryBucket: Decimal] = [:]
        historicalCategoryNet.reserveCapacity(16)
        var historicalCategoryCount: [CategoryBucket: Int] = [:]
        historicalCategoryCount.reserveCapacity(16)
        for tx in historicalTxs {
            let bucket = CategoryBucket(
                id: tx.category?.persistentModelID,
                name: tx.category?.name ?? "Uncategorized"
            )
            if tx.amount > 0, tx.category?.group?.type != .expense { continue }
            historicalCategoryNet[bucket, default: 0] += tx.amount
            historicalCategoryCount[bucket, default: 0] += 1
        }
        var historicalCategoryAvgOutflow: [CategoryBucket: Decimal] = [:]
        historicalCategoryAvgOutflow.reserveCapacity(historicalCategoryNet.count)
        for (bucket, net) in historicalCategoryNet {
            // Avoid strong claims without enough historical data.
            let count = historicalCategoryCount[bucket] ?? 0
            guard count >= 3 else { continue }
            let outflow = max(0, -net)
            historicalCategoryAvgOutflow[bucket] = outflow / 3
        }

        // Compare current to historical
        for (bucket, net) in categoryNet {
            let currentAmount = max(0, -net)
            if let historicalAvg = historicalCategoryAvgOutflow[bucket], historicalAvg > 0 {
                // Avoid noisy percent spikes on tiny amounts.
                guard currentAmount >= 50 || historicalAvg >= 50 else { continue }
                let delta = currentAmount - historicalAvg
                guard delta >= 50 else { continue }

                let increase = Double(truncating: ((currentAmount - historicalAvg) / historicalAvg) as NSNumber)

                if increase > 0.5 { // 50% increase
                    let percent = Int((increase * 100).rounded())
                    insights.append(Insight(
                        type: .unusualSpending,
                        title: "\(bucket.name) spending is high",
                        description: "\(currentAmount.formatted(.currency(code: currencyCode))) vs \(historicalAvg.formatted(.currency(code: currencyCode))) (up \(percent)%).",
                        why: "Compared to your average from the prior 3 months.",
                        severity: .warning,
                        actionable: true,
                        relatedCategoryID: bucket.id,
                        relatedCategoryName: bucket.name
                    ))
                }
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Budget Projection

    private func projectBudgetHealth(
        categories: [Category],
        transactions: [Transaction],
        dateRange: (Date, Date),
        currencyCode: String
    ) -> [Insight] {
        var insights: [Insight] = []

        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let rangeEnd = dateRange.1

        let clampedNow = min(max(Date(), rangeStart), rangeEnd)
        let totalDays = daysInclusive(from: rangeStart, to: rangeEnd, calendar: calendar)
        let daysPassed = daysInclusive(from: rangeStart, to: clampedNow, calendar: calendar)
        let daysRemaining = max(0, totalDays - daysPassed)

        guard daysRemaining > 0 && daysPassed > 0 else { return insights }

        // Find categories on track to exceed budget
        let expenseCategories = categories.filter { $0.group?.type == .expense && $0.assigned >= 25 }

        for category in expenseCategories {
            let net = transactions
                .filter { $0.category?.persistentModelID == category.persistentModelID && $0.kind == .standard && $0.account?.isTrackingOnly != true }
                .reduce(Decimal(0)) { $0 + $1.amount }
            let spent = max(0, -net)

            guard spent >= 10 else { continue }

            let dailyRate = spent / Decimal(daysPassed)
            let projectedTotal = dailyRate * Decimal(totalDays)

            if projectedTotal > category.assigned {
                insights.append(Insight(
                    type: .budgetProjection,
                    title: "\(category.name) budget at risk",
                    description: "Projected \(projectedTotal.formatted(.currency(code: currencyCode))) vs budget \(category.assigned.formatted(.currency(code: currencyCode))).",
                    why: "Based on \(daysPassed) day\(daysPassed == 1 ? "" : "s") of spend so far.",
                    severity: .warning,
                    actionable: true,
                    relatedCategoryID: category.persistentModelID,
                    relatedCategoryName: category.name
                ))
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Savings Opportunities

    private func identifySavingsOpportunities(
        transactions: [Transaction],
        currentIncome: Decimal,
        currentExpenses: Decimal,
        savingsRate: Double?,
        currencyCode: String
    ) -> [Insight] {
        var insights: [Insight] = []

        let computedIncome = incomeTotal(transactions: transactions)
        let computedExpenses = expenseOutflowTotal(transactions: transactions)
        let effectiveIncome = computedIncome
        let effectiveExpenses = computedExpenses

        let computedSavingsRate: Double? = {
            guard effectiveIncome > 0 else { return nil }
            let rate = (effectiveIncome - effectiveExpenses) / effectiveIncome
            return Double(truncating: rate as NSNumber)
        }()

        // 1. Low savings rate alert
        if let savingsRate = computedSavingsRate ?? savingsRate, effectiveIncome > 0 {
            if savingsRate < 0 {
                insights.append(Insight(
                    type: .savingsOpportunity,
                    title: "Spending over income",
                    description: "\(effectiveExpenses.formatted(.currency(code: currencyCode))) expenses vs \(effectiveIncome.formatted(.currency(code: currencyCode))) income.",
                    why: "This period’s expenses exceed your income.",
                    severity: .alert,
                    actionable: true
                ))
            } else if savingsRate < 0.10 {
                let targetSavings = effectiveIncome * 0.10 // 10% target
                let currentSavings = effectiveIncome - effectiveExpenses
                let gap = targetSavings - currentSavings

                insights.append(Insight(
                    type: .savingsOpportunity,
                    title: "Try saving a bit more",
                    description: "Save \(gap.formatted(.currency(code: currencyCode))) more to reach 10%.",
                    why: "Target savings is 10% of your income.",
                    severity: .info,
                    actionable: true
                ))
            }
        }

        // 2. Frequent small purchases
        let smallPurchases = transactions.filter { $0.amount < 0 && $0.kind == .standard && abs($0.amount) < 20 }
        if smallPurchases.count >= 15 { // 15+ small purchases
            let total = smallPurchases.reduce(Decimal(0)) { $0 + abs($1.amount) }

            insights.append(Insight(
                type: .savingsOpportunity,
                title: "Lots of small purchases",
                description: "\(smallPurchases.count) items under $20 add up to \(total.formatted(.currency(code: currencyCode))).",
                severity: .info,
                actionable: true
            ))
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Upcoming Bills Prediction

    private func predictUpcomingBills(transactions: [Transaction], currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.amount < 0 &&
            tx.kindRawValue == "Standard"
        }

        guard let rawAllTxs = try? modelContext.fetch(descriptor) else { return insights }
        let allTxs = rawAllTxs.filter { $0.account?.isTrackingOnly != true }

        // Group by normalized payee
        var grouped: [String: [Transaction]] = [:]
        for tx in allTxs {
            let normalizedPayee = PayeeNormalizer.normalizeForComparison(tx.payee)
            grouped[normalizedPayee, default: []].append(tx)
        }

        for (payee, txs) in grouped where txs.count >= 3 {
            let sortedTxs = txs.sorted { $0.date < $1.date }
            let intervals = zip(sortedTxs, sortedTxs.dropFirst()).map {
                $1.date.timeIntervalSince($0.date) / (24 * 3600) // Days between
            }

            guard let monthlyCheck = intervalsLookMonthly(intervals) else { continue }

            // Monthly bill (25-35 days interval)
            if monthlyCheck.isMonthly, let lastTx = sortedTxs.last {
                // Avoid labeling variable amounts as "usually $X".
                guard amountLooksStable(sortedTxs.map(\.amount)) else { continue }

                let calendar = Calendar.current
                let nextExpectedDate = calendar.date(byAdding: .day, value: monthlyCheck.medianDays, to: lastTx.date) ?? Date()
                let now = Date()
                let daysUntil = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: nextExpectedDate)).day ?? 0

                if daysUntil > 0 && daysUntil <= 7 { // Bill due within 7 days
                    let avgAmount = sortedTxs.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(sortedTxs.count)
                    let displayPayee = sortedTxs.last?.payee ?? payee

                    insights.append(Insight(
                        type: .upcomingBill,
                        title: "\(displayPayee) coming soon",
                        description: "Usually \(avgAmount.formatted(.currency(code: currencyCode))) in \(daysUntil) day\(daysUntil == 1 ? "" : "s").",
                        why: "Based on \(sortedTxs.count) payments about every \(monthlyCheck.medianDays) days.",
                        severity: .info,
                        actionable: true,
                        relatedPayee: displayPayee
                    ))
                }
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Spending Trends

    private func analyzeSpendingTrends(transactions: [Transaction], dateRange: (Date, Date), currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        let calendar = Calendar.current
        let comparison = previousComparisonRange(for: (start: dateRange.0, end: dateRange.1), calendar: calendar)
        let previousStart = comparison.start
        let previousEnd = comparison.endExclusive

        let standardRaw = TransactionKind.standard.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.date >= previousStart &&
                tx.date < previousEnd &&
                tx.kindRawValue == standardRaw
            }
        )

        guard let previousTxs = try? modelContext.fetch(descriptor) else { return insights }

        let currentOutflowTotal = expenseOutflowTotal(transactions: transactions)
        let previousOutflowTotal = expenseOutflowTotal(transactions: previousTxs)

        let currentAmount = roundedCurrency(currentOutflowTotal)
        let previousAmount = roundedCurrency(previousOutflowTotal)

        guard max(currentAmount, previousAmount) >= 50 else { return insights }

        let currentValue: Decimal
        let previousValue: Decimal
        switch comparison.kind {
        case .month, .year:
            currentValue = currentAmount
            previousValue = previousAmount
        case .rolling:
            let currentDays = daysInclusive(from: dateRange.0, to: dateRange.1, calendar: calendar)
            let previousDays = daysInclusive(from: previousStart, to: previousEnd.addingTimeInterval(-1), calendar: calendar)
            currentValue = currentAmount / Decimal(currentDays)
            previousValue = previousAmount / Decimal(previousDays)
        }

        let delta = currentValue - previousValue
        if abs(delta) <= 0.01 { return insights }

        if previousValue > 0 {
            let change = Double(truncating: (delta / previousValue) as NSNumber)

            if abs(change) > 0.15 { // 15% change
                let direction = change > 0 ? "up" : "down"
                let severity: Insight.Severity = change > 0 ? .warning : .info
                let percent = Int((abs(change) * 100).rounded())

                insights.append(Insight(
                    type: .spendingTrend,
                    title: "Spending is \(direction) \(percent)%",
                    description: "\(currentAmount.formatted(.currency(code: currencyCode))) vs \(previousAmount.formatted(.currency(code: currencyCode))) \(comparison.label).",
                    why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                    severity: severity,
                    actionable: change > 0
                ))
            }
        }

        return insights
    }

    // MARK: - Income Variation

    private func analyzeIncomeVariation(transactions: [Transaction], dateRange: (Date, Date), currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        let currentIncomeTotal = incomeTotal(transactions: transactions)

        let calendar = Calendar.current
        let comparison = previousComparisonRange(for: (start: dateRange.0, end: dateRange.1), calendar: calendar)
        let previousStart = comparison.start
        let previousEnd = comparison.endExclusive

        let standardRaw = TransactionKind.standard.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.date >= previousStart &&
                tx.date < previousEnd &&
                tx.kindRawValue == standardRaw
            }
        )

        guard let previousTxs = try? modelContext.fetch(descriptor) else { return insights }
        let previousIncomeTotal = incomeTotal(transactions: previousTxs)

        let currentAmount = roundedCurrency(currentIncomeTotal)
        let previousAmount = roundedCurrency(previousIncomeTotal)

        guard max(currentAmount, previousAmount) >= 50 else { return insights }

        let currentValue: Decimal
        let previousValue: Decimal
        switch comparison.kind {
        case .month, .year:
            currentValue = currentAmount
            previousValue = previousAmount
        case .rolling:
            let currentDays = daysInclusive(from: dateRange.0, to: dateRange.1, calendar: calendar)
            let previousDays = daysInclusive(from: previousStart, to: previousEnd.addingTimeInterval(-1), calendar: calendar)
            currentValue = currentAmount / Decimal(currentDays)
            previousValue = previousAmount / Decimal(previousDays)
        }

        let delta = currentValue - previousValue
        if abs(delta) <= 0.01 { return insights }

        if previousValue > 0, currentValue > 0 {
            let change = Double(truncating: (delta / previousValue) as NSNumber)
            let percent = Int((abs(change) * 100).rounded())

            if change < -0.10 { // 10% decrease
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is down \(percent)%",
                    description: "\(currentAmount.formatted(.currency(code: currencyCode))) vs \(previousAmount.formatted(.currency(code: currencyCode))) \(comparison.label).",
                    why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                    severity: .warning,
                    actionable: true
                ))
            } else if change > 0.10 { // 10% increase
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is up \(percent)%",
                    description: "\(currentAmount.formatted(.currency(code: currencyCode))) vs \(previousAmount.formatted(.currency(code: currencyCode))) \(comparison.label).",
                    why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                    severity: .info,
                    actionable: false
                ))
            }
        } else if previousAmount > 0, currentAmount == 0 {
            insights.append(Insight(
                type: .incomeVariation,
                title: "Income dropped to zero",
                description: "No income found for this period. It was \(previousAmount.formatted(.currency(code: currencyCode))) \(comparison.label).",
                why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                severity: .warning,
                actionable: true
            ))
        }

        return insights
    }
}
