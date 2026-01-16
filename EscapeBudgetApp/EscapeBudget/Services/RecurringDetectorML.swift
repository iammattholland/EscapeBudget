import Foundation
import SwiftData

/// ML-based recurring transaction detection service
@MainActor
final class RecurringDetectorML {
    private let modelContext: ModelContext

    struct RecurringSuggestion {
        let pattern: RecurringPattern
        let nextExpectedDate: Date?
        let confidence: Double
        let reason: String
    }

    struct Config {
        var minOccurrences: Int = 3
        var lookbackMonths: Int = 12
        var amountVarianceThreshold: Double = 0.15  // 15% variance allowed

        nonisolated init(minOccurrences: Int = 3, lookbackMonths: Int = 12, amountVarianceThreshold: Double = 0.15) {
            self.minOccurrences = minOccurrences
            self.lookbackMonths = lookbackMonths
            self.amountVarianceThreshold = amountVarianceThreshold
        }
    }

    private let config: Config

    init(modelContext: ModelContext, config: Config = Config()) {
        self.modelContext = modelContext
        self.config = config
    }

    /// Detect recurring patterns in transaction history
    func detectRecurringPatterns() async -> [RecurringPattern] {
        let startDate = Calendar.current.date(byAdding: .month, value: -config.lookbackMonths, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allTransactions = try? modelContext.fetch(descriptor) else { return [] }
        let transactions = allTransactions.filter { $0.kind == .standard }

        // Group transactions by payee
        var payeeGroups: [String: [Transaction]] = [:]
        for tx in transactions {
            let normalized = tx.payee.lowercased()
            payeeGroups[normalized, default: []].append(tx)
        }

        var detectedPatterns: [RecurringPattern] = []

        for (payee, txs) in payeeGroups {
            guard txs.count >= config.minOccurrences else { continue }

            // Sort by date
            let sorted = txs.sorted { $0.date < $1.date }

            // Analyze intervals between transactions
            if let pattern = analyzeIntervals(payee: payee, transactions: sorted) {
                detectedPatterns.append(pattern)
            }

            // Yield control periodically
            if detectedPatterns.count % 10 == 0 {
                await Task.yield()
            }
        }

        // Save new patterns
        for pattern in detectedPatterns {
            modelContext.insert(pattern)
        }

        _ = modelContext.safeSave(
            context: "RecurringDetectorML.detectPatterns",
            showErrorToUser: false
        )

        return detectedPatterns
    }

    /// Check if a transaction matches any recurring pattern
    func checkForRecurringMatch(_ transaction: Transaction) -> RecurringSuggestion? {
        let descriptor = FetchDescriptor<RecurringPattern>(
            predicate: #Predicate { $0.isActive }
        )

        guard let patterns = try? modelContext.fetch(descriptor) else { return nil }

        let payee = transaction.payee.lowercased()
        let amount = abs(transaction.amount)

        for pattern in patterns {
            // Check payee match
            guard pattern.payeePattern == payee else { continue }

            // Check amount match
            if let typicalAmount = pattern.typicalAmount {
                let diff = abs(amount - typicalAmount)
                let percentDiff = NSDecimalNumber(decimal: diff / typicalAmount).doubleValue

                guard percentDiff <= config.amountVarianceThreshold else { continue }
            }

            // Check date match
            if pattern.matchesDate(transaction.date) {
                // Update pattern
                pattern.lastDetectedDate = transaction.date
                pattern.occurrenceCount += 1
                pattern.confidence = min(1.0, pattern.confidence + 0.05)

                if let category = transaction.category {
                    pattern.category = category
                }

                _ = modelContext.safeSave(
                    context: "RecurringDetectorML.matchFound",
                    showErrorToUser: false
                )

                return RecurringSuggestion(
                    pattern: pattern,
                    nextExpectedDate: pattern.predictNextDate(),
                    confidence: pattern.confidence,
                    reason: "Matches \(pattern.frequency.rawValue) pattern"
                )
            }
        }

        return nil
    }

    /// Get upcoming recurring transactions
    func getUpcomingRecurring(days: Int = 30) -> [(pattern: RecurringPattern, expectedDate: Date)] {
        let descriptor = FetchDescriptor<RecurringPattern>(
            predicate: #Predicate { $0.isActive && $0.isReliable }
        )

        guard let patterns = try? modelContext.fetch(descriptor) else { return [] }

        let endDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()

        var upcoming: [(RecurringPattern, Date)] = []

        for pattern in patterns {
            if let nextDate = pattern.predictNextDate(),
               nextDate <= endDate && nextDate >= Date() {
                upcoming.append((pattern, nextDate))
            }
        }

        return upcoming.sorted { $0.1 < $1.1 }
    }

    // MARK: - Private Methods

    private func analyzeIntervals(payee: String, transactions: [Transaction]) -> RecurringPattern? {
        guard transactions.count >= config.minOccurrences else { return nil }

        // Calculate intervals between consecutive transactions
        var intervals: [Int] = []
        for i in 1..<transactions.count {
            let days = Calendar.current.dateComponents([.day], from: transactions[i-1].date, to: transactions[i].date).day ?? 0
            if days > 0 {
                intervals.append(days)
            }
        }

        guard !intervals.isEmpty else { return nil }

        // Calculate average interval
        let avgInterval = Double(intervals.reduce(0, +)) / Double(intervals.count)

        // Determine frequency
        let frequency: RecurringPattern.RecurringFrequency?

        if avgInterval >= 6 && avgInterval <= 8 {
            frequency = .weekly
        } else if avgInterval >= 12 && avgInterval <= 16 {
            frequency = .biweekly
        } else if avgInterval >= 25 && avgInterval <= 35 {
            frequency = .monthly
        } else if avgInterval >= 85 && avgInterval <= 95 {
            frequency = .quarterly
        } else if avgInterval >= 355 && avgInterval <= 375 {
            frequency = .yearly
        } else {
            frequency = nil
        }

        guard let freq = frequency else { return nil }

        // Create pattern
        let pattern = RecurringPattern(payee: payee, frequency: freq)

        // Set amount range
        let amounts = transactions.map { abs($0.amount) }
        pattern.minAmount = amounts.min()
        pattern.maxAmount = amounts.max()
        pattern.typicalAmount = amounts.reduce(Decimal(0), +) / Decimal(amounts.count)

        // Set last detected date
        pattern.lastDetectedDate = transactions.last?.date

        // Set category if consistent
        let categories = transactions.compactMap { $0.category }
        if let mostCommon = mostCommonElement(categories) {
            pattern.category = mostCommon
        }

        // Set day of month/week
        if freq == .monthly {
            let days = transactions.map { Calendar.current.component(.day, from: $0.date) }
            pattern.dayOfMonth = mostCommonElement(days)
        } else if freq == .weekly {
            let days = transactions.map { Calendar.current.component(.weekday, from: $0.date) }
            pattern.dayOfWeek = mostCommonElement(days)
        }

        pattern.occurrenceCount = transactions.count

        // Calculate confidence based on consistency
        let intervalVariance = intervals.map { Double($0) - avgInterval }.map { $0 * $0 }.reduce(0, +) / Double(intervals.count)
        let consistencyScore = max(0.0, 1.0 - (intervalVariance / (avgInterval * avgInterval)))
        pattern.confidence = consistencyScore

        return pattern.isReliable ? pattern : nil
    }

    private func mostCommonElement<T: Hashable>(_ array: [T]) -> T? {
        var counts: [T: Int] = [:]
        for element in array {
            counts[element, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
