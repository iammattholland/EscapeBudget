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
            return ComparisonRange(start: prevMonthStart, endExclusive: monthStart, label: "last month")
        }

        // Detect a full calendar year selection (e.g. year filter).
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: start)) ?? start
        let yearEndExclusive = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? end
        let yearEndInclusive = yearEndExclusive.addingTimeInterval(-1)
        let isFullYear = calendar.isDate(start, inSameDayAs: yearStart) && abs(end.timeIntervalSince(yearEndInclusive)) < 2

        if isFullYear {
            let prevYearStart = calendar.date(byAdding: .year, value: -1, to: yearStart) ?? yearStart
            return ComparisonRange(start: prevYearStart, endExclusive: yearStart, label: "last year")
        }

        // Fallback: compare against the immediately preceding range of the same duration.
        let duration = max(1, end.timeIntervalSince(start))
        let prevStart = start.addingTimeInterval(-duration)
        return ComparisonRange(start: prevStart, endExclusive: start, label: "previous period")
    }

    private func daysInclusive(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let delta = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, delta + 1)
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
        let expenses = transactions.filter { $0.amount < 0 && $0.kind == .standard }
        let grouped = Dictionary(grouping: expenses) { transaction in
            PayeeNormalizer.normalizeForComparison(transaction.payee)
        }

        for (payee, txs) in grouped where txs.count >= 2 {
            // Check if transactions occur at regular intervals
            let sortedDates = txs.map { $0.date }.sorted()
            if sortedDates.count >= 2 {
                let intervals = zip(sortedDates.dropFirst(), sortedDates).map { $1.timeIntervalSince($0) }
                let avgInterval = intervals.reduce(0, +) / Double(intervals.count)

                // If average interval is roughly monthly (25-35 days), it's likely recurring
                if avgInterval > 25 * 24 * 3600 && avgInterval < 35 * 24 * 3600 {
                    let avgAmount = txs.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(txs.count)
                    let displayPayee = txs.first?.payee ?? payee
                    let avgDays = Int((avgInterval / (24 * 3600)).rounded())

                    insights.append(Insight(
                        type: .recurringExpenseDetected,
                        title: "\(displayPayee) is recurring",
                        description: "About \(avgAmount.formatted(.currency(code: currencyCode))) monthly",
                        why: "Based on \(txs.count) payments ~ every \(avgDays) days.",
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
        let currentExpenses = transactions.filter { $0.amount < 0 && $0.kind == .standard }
        struct CategoryBucket: Hashable {
            let id: PersistentIdentifier?
            let name: String
        }

        var categorySpending: [CategoryBucket: Decimal] = [:]
        categorySpending.reserveCapacity(16)
        for tx in currentExpenses {
            let bucket = CategoryBucket(
                id: tx.category?.persistentModelID,
                name: tx.category?.name ?? "Uncategorized"
            )
            categorySpending[bucket, default: 0] += abs(tx.amount)
        }

        // Fetch historical data (3 full months before current period; aligns to calendar months).
        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let rangeMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: rangeStart)) ?? rangeStart
        let historicalStart = calendar.date(byAdding: .month, value: -3, to: rangeMonthStart) ?? rangeMonthStart
        let historicalEnd = rangeMonthStart

        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.date >= historicalStart &&
            tx.date < historicalEnd &&
            tx.amount < 0 &&
            tx.kindRawValue == "Standard"
        }

        guard let rawHistoricalTxs = try? modelContext.fetch(descriptor) else { return insights }
        let historicalTxs = rawHistoricalTxs.filter { $0.account?.isTrackingOnly != true }

        var historicalCategorySpending: [CategoryBucket: Decimal] = [:]
        historicalCategorySpending.reserveCapacity(16)
        for tx in historicalTxs {
            let bucket = CategoryBucket(
                id: tx.category?.persistentModelID,
                name: tx.category?.name ?? "Uncategorized"
            )
            historicalCategorySpending[bucket, default: 0] += abs(tx.amount)
        }
        for (bucket, total) in historicalCategorySpending {
            historicalCategorySpending[bucket] = total / 3
        }

        // Compare current to historical
        for (bucket, currentAmount) in categorySpending {
            if let historicalAvg = historicalCategorySpending[bucket], historicalAvg > 0 {
                let increase = Double(truncating: ((currentAmount - historicalAvg) / historicalAvg) as NSNumber)

                if increase > 0.5 { // 50% increase
                    let percent = Int((increase * 100).rounded())
                    insights.append(Insight(
                        type: .unusualSpending,
                        title: "\(bucket.name) spending is high",
                        description: "\(currentAmount.formatted(.currency(code: currencyCode))) vs \(historicalAvg.formatted(.currency(code: currencyCode))) (up \(percent)%)",
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
        let expenseCategories = categories.filter { $0.group?.type == .expense && $0.assigned > 0 }

        for category in expenseCategories {
            let spent = transactions
                .filter { $0.category?.persistentModelID == category.persistentModelID && $0.amount < 0 }
                .reduce(Decimal(0)) { $0 + abs($1.amount) }

            let dailyRate = spent / Decimal(daysPassed)
            let projectedTotal = dailyRate * Decimal(totalDays)

            if projectedTotal > category.assigned {
                let overBy = projectedTotal - category.assigned

                insights.append(Insight(
                    type: .budgetProjection,
                    title: "\(category.name) budget at risk",
                    description: "Projected \(projectedTotal.formatted(.currency(code: currencyCode))) vs budget \(category.assigned.formatted(.currency(code: currencyCode)))",
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

        // 1. Low savings rate alert
        if let savingsRate, currentIncome > 0 {
            if savingsRate < 0 {
                insights.append(Insight(
                    type: .savingsOpportunity,
                    title: "Spending over income",
                    description: "\(currentExpenses.formatted(.currency(code: currencyCode))) expenses vs \(currentIncome.formatted(.currency(code: currencyCode))) income",
                    why: "This period’s expenses exceed your income.",
                    severity: .alert,
                    actionable: true
                ))
            } else if savingsRate < 0.10 {
                let targetSavings = currentIncome * 0.10 // 10% target
                let currentSavings = currentIncome - currentExpenses
                let gap = targetSavings - currentSavings

                insights.append(Insight(
                    type: .savingsOpportunity,
                    title: "Try saving a bit more",
                    description: "Save \(gap.formatted(.currency(code: currencyCode))) more to reach 10%",
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
                description: "\(smallPurchases.count) items under $20 add up to \(total.formatted(.currency(code: currencyCode)))",
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
            let intervals = zip(sortedTxs.dropFirst(), sortedTxs).map {
                $1.date.timeIntervalSince($0.date) / (24 * 3600) // Days between
            }

            let avgDaysBetween = intervals.reduce(0, +) / Double(intervals.count)

            // Monthly bill (25-35 days interval)
            if avgDaysBetween > 25 && avgDaysBetween < 35, let lastTx = sortedTxs.last {
                let nextExpectedDate = Calendar.current.date(byAdding: .day, value: Int(avgDaysBetween), to: lastTx.date) ?? Date()
                let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: nextExpectedDate).day ?? 0

                if daysUntil > 0 && daysUntil <= 7 { // Bill due within 7 days
                    let avgAmount = sortedTxs.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(sortedTxs.count)
                    let displayPayee = sortedTxs.last?.payee ?? payee

                    insights.append(Insight(
                        type: .upcomingBill,
                        title: "\(displayPayee) coming soon",
                        description: "Usually \(avgAmount.formatted(.currency(code: currencyCode))) in \(daysUntil) day\(daysUntil == 1 ? "" : "s")",
                        severity: .info,
                        actionable: false,
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

        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.date >= previousStart &&
            tx.date < previousEnd &&
            tx.amount < 0 &&
            tx.kindRawValue == "Standard"
        }

        guard let rawPreviousTxs = try? modelContext.fetch(descriptor) else { return insights }
        let previousTxs = rawPreviousTxs.filter { $0.account?.isTrackingOnly != true }

        let currentSpending = transactions
            .filter { $0.amount < 0 && $0.kind == .standard && $0.account?.isTrackingOnly != true }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }

        let previousSpending = previousTxs.reduce(Decimal(0)) { $0 + abs($1.amount) }

        if previousSpending > 0 {
            let change = Double(truncating: ((currentSpending - previousSpending) / previousSpending) as NSNumber)

            if abs(change) > 0.15 { // 15% change
                let direction = change > 0 ? "up" : "down"
                let severity: Insight.Severity = change > 0 ? .warning : .info
                let percent = Int((abs(change) * 100).rounded())

                insights.append(Insight(
                    type: .spendingTrend,
                    title: "Spending is \(direction) \(percent)%",
                    description: "\(currentSpending.formatted(.currency(code: currencyCode))) vs \(previousSpending.formatted(.currency(code: currencyCode))) \(comparison.label)",
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

        // Filter income transactions (positive amounts with income category type)
        let currentIncome = transactions.filter { tx in
            guard tx.amount > 0 else { return false }
            return tx.kind == .standard &&
                tx.account?.isTrackingOnly != true &&
                tx.category?.group?.type == .income
        }.reduce(Decimal(0)) { $0 + $1.amount }

        let calendar = Calendar.current
        let comparison = previousComparisonRange(for: (start: dateRange.0, end: dateRange.1), calendar: calendar)
        let previousStart = comparison.start
        let previousEnd = comparison.endExclusive

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.date >= previousStart &&
                tx.date < previousEnd &&
                tx.amount > 0 &&
                tx.kindRawValue == "Standard"
            }
        )

        guard let rawPreviousTxs = try? modelContext.fetch(descriptor) else { return insights }
        let previousTxs = rawPreviousTxs.filter { $0.account?.isTrackingOnly != true }

        let previousIncome = previousTxs
            .filter { $0.category?.group?.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }

        if previousIncome > 0 && currentIncome > 0 {
            let change = Double(truncating: ((currentIncome - previousIncome) / previousIncome) as NSNumber)
            let percent = Int((abs(change) * 100).rounded())

            if change < -0.10 { // 10% decrease
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is down \(percent)%",
                    description: "\(currentIncome.formatted(.currency(code: currencyCode))) vs \(previousIncome.formatted(.currency(code: currencyCode))) \(comparison.label)",
                    why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                    severity: .warning,
                    actionable: true
                ))
            } else if change > 0.10 { // 10% increase
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is up \(Int((change * 100).rounded()))%",
                    description: "\(currentIncome.formatted(.currency(code: currencyCode))) vs \(previousIncome.formatted(.currency(code: currencyCode))) \(comparison.label)",
                    why: "Compared to \(comparison.label) (\(formattedShortDateRange(start: previousStart, endExclusive: previousEnd, calendar: calendar))).",
                    severity: .info,
                    actionable: false
                ))
            }
        }

        return insights
    }
}
