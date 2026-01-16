import Foundation
import SwiftData

/// ML-based category prediction service
@MainActor
final class CategoryPredictor {
    private let modelContext: ModelContext
    let patternLearner: CategoryPatternLearner
    private let scoringModel: CategoryScoringModel

    struct Prediction {
        let category: Category
        let confidence: Double
        let matchedPattern: CategoryPattern?
        let reason: String
    }

    struct Config {
        var minConfidenceThreshold: Double = 0.5
        var useMLScoring: Bool = true

        nonisolated init(minConfidenceThreshold: Double = 0.5, useMLScoring: Bool = true) {
            self.minConfidenceThreshold = minConfidenceThreshold
            self.useMLScoring = useMLScoring
        }
    }

    private let config: Config

    init(modelContext: ModelContext, config: Config = Config()) {
        self.modelContext = modelContext
        self.patternLearner = CategoryPatternLearner(modelContext: modelContext)
        self.scoringModel = CategoryScoringModel()
        self.config = config
    }

    /// Predict category for a transaction
    func predictCategory(for transaction: Transaction) -> Prediction? {
        guard config.useMLScoring else { return nil }

        // Don't predict for transfers
        guard transaction.kind == .standard else { return nil }

        // Extract features
        let features = CategoryFeatures(transaction: transaction)

        // Load learned patterns
        let allPatterns = patternLearner.fetchReliablePatterns()
        guard !allPatterns.isEmpty else { return nil }

        // Score against patterns
        let (score, matchedPattern) = scoringModel.scoreMatch(features, patterns: allPatterns)

        // Convert score to confidence (normalize to 0-1)
        let maxPossibleScore = 200.0  // Approximate max score from weights
        let confidence = min(1.0, score / maxPossibleScore)

        guard confidence >= config.minConfidenceThreshold,
              let pattern = matchedPattern,
              let category = pattern.category else {
            return nil
        }

        // Generate reason
        let reason = generateReason(pattern: pattern, features: features)

        return Prediction(
            category: category,
            confidence: confidence,
            matchedPattern: pattern,
            reason: reason
        )
    }

    /// Get top N category predictions
    func predictTopCategories(for transaction: Transaction, limit: Int = 3) -> [Prediction] {
        guard config.useMLScoring else { return [] }
        guard transaction.kind == .standard else { return [] }

        let features = CategoryFeatures(transaction: transaction)
        let allPatterns = patternLearner.fetchReliablePatterns()
        guard !allPatterns.isEmpty else { return [] }

        // Score all patterns
        var predictions: [Prediction] = []
        var seenCategories = Set<PersistentIdentifier>()

        for pattern in allPatterns {
            guard let category = pattern.category else { continue }

            // Skip if we already have a prediction for this category
            guard !seenCategories.contains(category.persistentModelID) else { continue }

            let score = scoringModel.scoreAgainstPattern(features, pattern: pattern)
            let maxPossibleScore = 200.0
            let confidence = min(1.0, score / maxPossibleScore)

            if confidence >= config.minConfidenceThreshold {
                let reason = generateReason(pattern: pattern, features: features)
                predictions.append(Prediction(
                    category: category,
                    confidence: confidence,
                    matchedPattern: pattern,
                    reason: reason
                ))
                seenCategories.insert(category.persistentModelID)
            }
        }

        // Sort by confidence and return top N
        return predictions
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }

    /// Learn from user's category assignment
    func learnFromCategorization(transaction: Transaction, wasAutoDetected: Bool) {
        guard let category = transaction.category else { return }
        patternLearner.learnFromCategorization(
            transaction: transaction,
            category: category,
            wasAutoDetected: wasAutoDetected
        )
    }

    /// Learn from rejected suggestion
    func learnFromRejection(transaction: Transaction, rejectedCategory: Category) {
        patternLearner.learnFromRejection(
            transaction: transaction,
            rejectedCategory: rejectedCategory
        )
    }

    // MARK: - Helper Methods

    private func generateReason(pattern: CategoryPattern, features: CategoryFeatures) -> String {
        var reasons: [String] = []

        // Payee match
        if features.payee == pattern.payeePattern {
            reasons.append("exact payee match")
        } else if features.payee.contains(pattern.payeePattern) {
            reasons.append("similar payee")
        }

        // Confidence
        if pattern.isReliable {
            reasons.append("\(pattern.successfulMatches) past matches")
        }

        // Amount
        if let typicalAmount = pattern.typicalAmount {
            let diff = abs(features.amount - typicalAmount)
            let percentDiff = NSDecimalNumber(decimal: diff / max(features.amount, typicalAmount)).doubleValue
            if percentDiff < 0.1 {
                reasons.append("typical amount")
            }
        }

        return reasons.isEmpty ? "learned pattern" : reasons.joined(separator: ", ")
    }
}
