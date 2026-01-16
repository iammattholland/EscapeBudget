import Foundation
import SwiftData

/// Generates predictive insights and smart notifications based on transaction patterns
@MainActor
struct PredictiveInsightsEngine {
    let modelContext: ModelContext

    struct Insight: Identifiable, Hashable {
        let id = UUID()
        let type: InsightType
        let title: String
        let description: String
        let severity: Severity
        let actionable: Bool

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
        insights.append(contentsOf: detectUnusualSpending(transactions: transactions, dateRange: dateRange))

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

                    insights.append(Insight(
                        type: .recurringExpenseDetected,
                        title: "\(displayPayee) is recurring",
                        description: "About \(avgAmount.formatted(.currency(code: currencyCode))) monthly",
                        severity: .info,
                        actionable: true
                    ))
                }
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Unusual Spending Detection

    private func detectUnusualSpending(transactions: [Transaction], dateRange: (Date, Date)) -> [Insight] {
        var insights: [Insight] = []

        // Get historical average spending per category
        let currentExpenses = transactions.filter { $0.amount < 0 && $0.kind == .standard }
        let categorySpending = Dictionary(grouping: currentExpenses) { $0.category?.name ?? "Uncategorized" }
            .mapValues { txs in txs.reduce(Decimal(0)) { $0 + abs($1.amount) } }

        // Fetch historical data (last 3 months before current period)
        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let historicalStart = calendar.date(byAdding: .month, value: -3, to: rangeStart) ?? rangeStart
        let historicalEnd = rangeStart

        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.date >= historicalStart && tx.date < historicalEnd && tx.amount < 0
        }

        guard let historicalTxs = try? modelContext.fetch(descriptor) else { return insights }

        let historicalCategorySpending = Dictionary(grouping: historicalTxs) { $0.category?.name ?? "Uncategorized" }
            .mapValues { txs in txs.reduce(Decimal(0)) { $0 + abs($1.amount) } / 3 } // Average per month

        // Compare current to historical
        for (category, currentAmount) in categorySpending {
            if let historicalAvg = historicalCategorySpending[category], historicalAvg > 0 {
                let increase = Double(truncating: ((currentAmount - historicalAvg) / historicalAvg) as NSNumber)

                if increase > 0.5 { // 50% increase
                    insights.append(Insight(
                        type: .unusualSpending,
                        title: "\(category) spending is high",
                        description: "Up \(Int(increase * 100))% from your usual",
                        severity: .warning,
                        actionable: true
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
        let totalDays = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 30
        let daysPassed = calendar.dateComponents([.day], from: rangeStart, to: Date()).day ?? 1
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
                    description: "On track to go over by \(overBy.formatted(.currency(code: currencyCode)))",
                    severity: .warning,
                    actionable: true
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
                    description: "You're spending more than you earned this period",
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
                    severity: .info,
                    actionable: true
                ))
            }
        }

        // 2. Frequent small purchases
        let smallPurchases = transactions.filter { $0.amount < 0 && abs($0.amount) < 20 }
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
            tx.amount < 0
        }

        guard let allTxs = try? modelContext.fetch(descriptor) else { return insights }

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
                        actionable: false
                    ))
                }
            }
        }

        return Array(insights.prefix(1)) // Limit to top insight
    }

    // MARK: - Spending Trends

    private func analyzeSpendingTrends(transactions: [Transaction], dateRange: (Date, Date), currencyCode: String) -> [Insight] {
        var insights: [Insight] = []

        // Compare to previous period
        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let rangeEnd = dateRange.1
        let periodLength = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 30
        let previousStart = calendar.date(byAdding: .day, value: -periodLength, to: rangeStart) ?? rangeStart
        let previousEnd = rangeStart

        var descriptor = FetchDescriptor<Transaction>()
        descriptor.predicate = #Predicate<Transaction> { tx in
            tx.date >= previousStart && tx.date < previousEnd && tx.amount < 0
        }

        guard let previousTxs = try? modelContext.fetch(descriptor) else { return insights }

        let currentSpending = transactions.filter { $0.amount < 0 && $0.kind == .standard }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }

        let previousSpending = previousTxs.reduce(Decimal(0)) { $0 + abs($1.amount) }

        if previousSpending > 0 {
            let change = Double(truncating: ((currentSpending - previousSpending) / previousSpending) as NSNumber)

            if abs(change) > 0.15 { // 15% change
                let direction = change > 0 ? "up" : "down"
                let severity: Insight.Severity = change > 0 ? .warning : .info

                insights.append(Insight(
                    type: .spendingTrend,
                    title: "Spending is \(direction) \(Int(abs(change) * 100))%",
                    description: "\(currentSpending.formatted(.currency(code: currencyCode))) vs \(previousSpending.formatted(.currency(code: currencyCode))) last period",
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
            return tx.category?.group?.type == .income
        }.reduce(Decimal(0)) { $0 + $1.amount }

        // Compare to previous period
        let calendar = Calendar.current
        let rangeStart = dateRange.0
        let rangeEnd = dateRange.1
        let periodLength = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 30
        let previousStart = calendar.date(byAdding: .day, value: -periodLength, to: rangeStart) ?? rangeStart
        let previousEnd = rangeStart

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.date >= previousStart && tx.date < previousEnd && tx.amount > 0
            }
        )

        guard let previousTxs = try? modelContext.fetch(descriptor) else { return insights }

        let previousIncome = previousTxs.filter { tx in
            tx.category?.group?.type == .income
        }.reduce(Decimal(0)) { $0 + $1.amount }

        if previousIncome > 0 && currentIncome > 0 {
            let change = Double(truncating: ((currentIncome - previousIncome) / previousIncome) as NSNumber)

            if change < -0.10 { // 10% decrease
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is down \(Int(abs(change) * 100))%",
                    description: "Watch your spending this period",
                    severity: .warning,
                    actionable: true
                ))
            } else if change > 0.10 { // 10% increase
                insights.append(Insight(
                    type: .incomeVariation,
                    title: "Income is up \(Int(change * 100))%",
                    description: "You earned \(currentIncome.formatted(.currency(code: currencyCode))) this period",
                    severity: .info,
                    actionable: false
                ))
            }
        }

        return insights
    }
}
