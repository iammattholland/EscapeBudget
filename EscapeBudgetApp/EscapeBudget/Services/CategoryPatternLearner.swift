import Foundation
import SwiftData

/// Service for learning category patterns from user categorization history
@MainActor
final class CategoryPatternLearner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Learn from a user's category assignment
    func learnFromCategorization(
        transaction: Transaction,
        category: Category,
        wasAutoDetected: Bool
    ) {
        let payeePattern = normalizePayee(transaction.payee)

        // Find or create pattern for this payee + category
        var pattern = fetchPattern(payee: payeePattern, category: category)
            ?? createPattern(payee: payeePattern, category: category)

        // Update usage statistics
        pattern.lastUsedAt = Date()
        pattern.useCount += 1
        pattern.successfulMatches += 1
        pattern.lastSuccessDate = Date()

        if wasAutoDetected {
            pattern.autoDetectedCount += 1
        } else {
            pattern.manualCategoryCount += 1
        }

        // Learn from this example
        updateAmountRange(pattern: &pattern, transaction: transaction)
        updateTimingPattern(pattern: &pattern, transaction: transaction)
        updateMemoKeywords(pattern: &pattern, transaction: transaction)

        // Save changes
        _ = modelContext.safeSave(
            context: "CategoryPatternLearner.learnFromCategorization",
            showErrorToUser: false
        )
    }

    /// Learn from a rejected category suggestion
    func learnFromRejection(
        transaction: Transaction,
        rejectedCategory: Category
    ) {
        let payeePattern = normalizePayee(transaction.payee)

        // Find pattern if it exists
        guard let pattern = fetchPattern(payee: payeePattern, category: rejectedCategory) else { return }

        // Update rejection statistics
        pattern.rejectedMatches += 1
        pattern.lastRejectionDate = Date()

        // If this pattern is getting rejected frequently, reset learned parameters
        if pattern.rejectedMatches > pattern.successfulMatches * 2 {
            pattern.minAmount = nil
            pattern.maxAmount = nil
            pattern.typicalAmount = nil
            pattern.commonDayOfWeek = nil
            pattern.commonMemoKeywords = nil
        }

        _ = modelContext.safeSave(
            context: "CategoryPatternLearner.learnFromRejection",
            showErrorToUser: false
        )
    }

    /// Bulk learn from existing transaction history
    func learnFromHistory(limit: Int = 500) async {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allTransactions = try? modelContext.fetch(descriptor) else { return }
        let transactions = allTransactions
            .filter { $0.kind == .standard && $0.category != nil }
            .prefix(limit)

        var processedCount = 0
        for transaction in transactions {
            guard let category = transaction.category else { continue }

            learnFromCategorization(
                transaction: transaction,
                category: category,
                wasAutoDetected: false
            )

            processedCount += 1

            // Yield control periodically
            if processedCount % 50 == 0 {
                await Task.yield()
            }
        }
    }

    /// Fetch all learned patterns
    func fetchAllPatterns() -> [CategoryPattern] {
        let descriptor = FetchDescriptor<CategoryPattern>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch patterns for a specific payee
    func fetchPatterns(forPayee payee: String) -> [CategoryPattern] {
        let variants = normalizePayeeVariants(payee)
        let descriptor = FetchDescriptor<CategoryPattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []
        let variantSet = Set(variants)
        return allPatterns.filter { variantSet.contains($0.payeePattern) }
    }

    /// Fetch reliable patterns (confidence > 0.7, at least 3 successes)
    func fetchReliablePatterns() -> [CategoryPattern] {
        fetchAllPatterns().filter { $0.isReliable }
    }

    // MARK: - Pattern Updates

    private func updateAmountRange(pattern: inout CategoryPattern, transaction: Transaction) {
        let amount = abs(transaction.amount)

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

        // Update typical amount (running average)
        if let currentTypical = pattern.typicalAmount {
            let newTypical = (currentTypical * Decimal(pattern.useCount - 1) + amount) / Decimal(pattern.useCount)
            pattern.typicalAmount = newTypical
        } else {
            pattern.typicalAmount = amount
        }
    }

    private func updateTimingPattern(pattern: inout CategoryPattern, transaction: Transaction) {
        let dayOfWeek = Calendar.current.component(.weekday, from: transaction.date)

        // Track most common day of week (simple mode tracking)
        if pattern.commonDayOfWeek == nil {
            pattern.commonDayOfWeek = dayOfWeek
        } else if pattern.commonDayOfWeek == dayOfWeek {
            // Reinforce existing pattern
        } else {
            // For simplicity, keep the current pattern unless we want to build a frequency map
        }
    }

    private func updateMemoKeywords(pattern: inout CategoryPattern, transaction: Transaction) {
        guard let memo = transaction.memo, !memo.isEmpty else { return }

        let memoWords = memo.lowercased()
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count >= 3 }  // Only keep meaningful words

        var keywords = pattern.commonMemoKeywords ?? []

        for word in memoWords {
            if !keywords.contains(word) {
                keywords.append(word)
                if keywords.count > 10 {
                    keywords.removeFirst()
                }
            }
        }

        if !keywords.isEmpty {
            pattern.commonMemoKeywords = keywords
        }
    }

    // MARK: - Helper Methods

    private func normalizePayee(_ payee: String) -> String {
        normalizePayeeVariants(payee).first ?? ""
    }

    private func fetchPattern(payee: String, category: Category) -> CategoryPattern? {
        let descriptor = FetchDescriptor<CategoryPattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []
        let variants = Set(normalizePayeeVariants(payee))
        return allPatterns.first { pattern in
            variants.contains(pattern.payeePattern) && pattern.category?.persistentModelID == category.persistentModelID
        }
    }

    private func createPattern(payee: String, category: Category) -> CategoryPattern {
        let normalized = normalizePayeeVariants(payee).first ?? payee
        let pattern = CategoryPattern(category: category, payeePattern: normalized)
        modelContext.insert(pattern)
        return pattern
    }

    private func normalizePayeeVariants(_ payee: String) -> [String] {
        let trimmedLower = payee
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let comparison = PayeeNormalizer.normalizeForComparison(payee)

        var variants: [String] = []
        if !comparison.isEmpty { variants.append(comparison) }
        if !trimmedLower.isEmpty, trimmedLower != comparison { variants.append(trimmedLower) }
        return variants
    }

    /// Clean up old, unreliable patterns
    func cleanupUnreliablePatterns(olderThan days: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<CategoryPattern>()
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
            context: "CategoryPatternLearner.cleanup",
            showErrorToUser: false
        )
    }
}
