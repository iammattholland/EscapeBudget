import Foundation
import SwiftData

/// Service for learning transfer patterns from user confirmations and rejections
@MainActor
final class TransferPatternLearner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Learn from a confirmed transfer link
    func learnFromConfirmation(
        debit: Transaction,
        credit: Transaction,
        wasAutoDetected: Bool
    ) {
        let accountPairID = makeAccountPairID(from: debit, to: credit)

        // Find or create pattern for this account pair
        var pattern = fetchPattern(for: accountPairID) ?? createPattern(for: accountPairID)

        // Update usage statistics
        pattern.lastUsedAt = Date()
        pattern.useCount += 1
        pattern.successfulMatches += 1
        pattern.lastSuccessDate = Date()

        if wasAutoDetected {
            pattern.autoDetectedCount += 1
        } else {
            pattern.manualLinkCount += 1
        }

        // Learn from this example
        updateAmountRange(pattern: &pattern, debit: debit, credit: credit)
        updateTimingPattern(pattern: &pattern, debit: debit, credit: credit)
        updateTextPatterns(pattern: &pattern, debit: debit, credit: credit)
        updateCalendarPattern(pattern: &pattern, debit: debit, credit: credit)

        // Save changes
        _ = modelContext.safeSave(
            context: "TransferPatternLearner.learnFromConfirmation",
            showErrorToUser: false
        )
    }

    /// Learn from a rejected transfer suggestion
    func learnFromRejection(
        debit: Transaction,
        credit: Transaction,
        wasAutoSuggested: Bool
    ) {
        let accountPairID = makeAccountPairID(from: debit, to: credit)

        // Find pattern if it exists
        guard let pattern = fetchPattern(for: accountPairID) else { return }

        // Update rejection statistics
        pattern.rejectedMatches += 1
        pattern.lastRejectionDate = Date()

        // If this pattern is getting rejected frequently, mark it as unreliable
        if pattern.rejectedMatches > pattern.successfulMatches * 2 {
            // Clear learned parameters to force re-learning
            pattern.minAmount = nil
            pattern.maxAmount = nil
            pattern.minHoursBetween = nil
            pattern.maxHoursBetween = nil
        }

        _ = modelContext.safeSave(
            context: "TransferPatternLearner.learnFromRejection",
            showErrorToUser: false
        )
    }

    /// Fetch all learned patterns
    func fetchAllPatterns() -> [TransferPattern] {
        let descriptor = FetchDescriptor<TransferPattern>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch patterns for a specific account pair
    func fetchPattern(for accountPairID: String) -> TransferPattern? {
        let descriptor = FetchDescriptor<TransferPattern>(
            predicate: #Predicate { $0.accountPairID == accountPairID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Fetch reliable patterns (confidence > 0.7, at least 3 successes)
    func fetchReliablePatterns() -> [TransferPattern] {
        fetchAllPatterns().filter { $0.isReliable }
    }

    // MARK: - Pattern Updates

    private func updateAmountRange(pattern: inout TransferPattern, debit: Transaction, credit: Transaction) {
        let amount = abs(debit.amount)
        let fee = abs(abs(debit.amount) - abs(credit.amount))

        // Update amount range
        if let currentMin = pattern.minAmount {
            pattern.minAmount = min(currentMin, amount)
        } else {
            pattern.minAmount = amount
        }

        if let currentMax = pattern.maxAmount {
            pattern.maxAmount = max(currentMax, amount)
        } else {
            pattern.maxAmount = amount
        }

        // Learn common fee amount
        if fee > 0 && fee < 20 {  // Reasonable fee range
            if let commonFee = pattern.commonFeeAmount {
                // Average with existing fee
                pattern.commonFeeAmount = (commonFee + fee) / 2
            } else {
                pattern.commonFeeAmount = fee
            }
        }
    }

    private func updateTimingPattern(pattern: inout TransferPattern, debit: Transaction, credit: Transaction) {
        let hoursBetween = abs(debit.date.timeIntervalSince(credit.date)) / 3600.0

        // Update hours between range
        if let currentMin = pattern.minHoursBetween {
            pattern.minHoursBetween = min(currentMin, hoursBetween)
        } else {
            pattern.minHoursBetween = hoursBetween
        }

        if let currentMax = pattern.maxHoursBetween {
            pattern.maxHoursBetween = max(currentMax, hoursBetween)
        } else {
            pattern.maxHoursBetween = hoursBetween
        }

        // Update typical hours (running average)
        if let currentTypical = pattern.typicalHoursBetween {
            let newTypical = (currentTypical * Double(pattern.useCount - 1) + hoursBetween) / Double(pattern.useCount)
            pattern.typicalHoursBetween = newTypical
        } else {
            pattern.typicalHoursBetween = hoursBetween
        }
    }

    private func updateTextPatterns(pattern: inout TransferPattern, debit: Transaction, credit: Transaction) {
        // Extract meaningful payee patterns
        let payee1 = debit.payee.lowercased()
        let payee2 = credit.payee.lowercased()

        // Find common substrings (simplified - could use more sophisticated NLP)
        let words1 = Set(payee1.split(separator: " ").map { String($0) })
        let words2 = Set(payee2.split(separator: " ").map { String($0) })
        let commonWords = words1.intersection(words2)

        // Add common words to payee patterns (limit to 10 patterns)
        for word in commonWords {
            if word.count >= 3 && !pattern.commonPayeePatterns.contains(word) {
                pattern.commonPayeePatterns.append(word)
                if pattern.commonPayeePatterns.count > 10 {
                    pattern.commonPayeePatterns.removeFirst()
                }
            }
        }

        // Learn memo keywords if present
        if let memo1 = debit.memo, let memo2 = credit.memo {
            let memoWords1 = Set(memo1.lowercased().split(separator: " ").map { String($0) })
            let memoWords2 = Set(memo2.lowercased().split(separator: " ").map { String($0) })
            let commonMemoWords = memoWords1.intersection(memoWords2)

            if !commonMemoWords.isEmpty {
                var keywords = pattern.commonMemoKeywords ?? []
                for word in commonMemoWords {
                    if word.count >= 3 && !keywords.contains(word) {
                        keywords.append(word)
                        if keywords.count > 10 {
                            keywords.removeFirst()
                        }
                    }
                }
                pattern.commonMemoKeywords = keywords
            }
        }
    }

    private func updateCalendarPattern(pattern: inout TransferPattern, debit: Transaction, credit: Transaction) {
        let calendar = Calendar.current
        let day = normalizedDayOfMonth(from: debit.date, calendar: calendar)

        pattern.dayOfMonthSampleCount += 1

        guard let current = pattern.commonDayOfMonth else {
            pattern.commonDayOfMonth = day
            pattern.dayOfMonthMatchCount = 1
            return
        }

        if current == day {
            pattern.dayOfMonthMatchCount += 1
        } else {
            pattern.dayOfMonthMatchCount = max(0, pattern.dayOfMonthMatchCount - 1)
            if pattern.dayOfMonthMatchCount == 0 {
                pattern.commonDayOfMonth = day
                pattern.dayOfMonthMatchCount = 1
            }
        }
    }

    // MARK: - Helper Methods

    private func makeAccountPairID(from debit: Transaction, to credit: Transaction) -> String {
        let account1ID = debit.account?.persistentModelID.hashValue ?? 0
        let account2ID = credit.account?.persistentModelID.hashValue ?? 0
        return "\(min(account1ID, account2ID))-\(max(account1ID, account2ID))"
    }

    private func normalizedDayOfMonth(from date: Date, calendar: Calendar) -> Int {
        let day = calendar.component(.day, from: date)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        if day >= max(1, daysInMonth - 1) {
            return 0 // end-of-month bucket
        }
        return day
    }

    private func createPattern(for accountPairID: String) -> TransferPattern {
        let pattern = TransferPattern(accountPairID: accountPairID)
        modelContext.insert(pattern)
        return pattern
    }

    /// Clean up old, unreliable patterns
    func cleanupUnreliablePatterns(olderThan days: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<TransferPattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []

        for pattern in allPatterns {
            // Delete patterns that are old and have low confidence
            if pattern.lastUsedAt < cutoffDate && !pattern.isReliable {
                modelContext.delete(pattern)
            }

            // Or patterns that have been rejected too many times
            if pattern.rejectedMatches > 10 && pattern.rejectedMatches > pattern.successfulMatches * 3 {
                modelContext.delete(pattern)
            }
        }

        _ = modelContext.safeSave(
            context: "TransferPatternLearner.cleanup",
            showErrorToUser: false
        )
    }
}
