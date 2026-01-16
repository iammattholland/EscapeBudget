import Foundation
import SwiftData

/// ML-based scoring model for transfer detection using learned patterns
@MainActor
final class TransferScoringModel {
    private let modelContext: ModelContext

    /// Weights for scoring features (can be adjusted based on learning)
    struct Weights {
        // Amount scoring
        var amountExactMatch: Double = 50.0
        var amountFeeAdjusted: Double = 35.0
        var amountClose: Double = 20.0

        // Temporal scoring
        var withinSameDay: Double = 25.0
        var withinWeek: Double = 15.0
        var hoursBetweenOptimal: Double = 20.0  // Peak at 0-24 hours

        // Text similarity
        var payeeJaccardSimilarity: Double = 15.0
        var memoSimilarity: Double = 10.0
        var hasTransferKeywords: Double = 12.0

        // Account features
        var accountTypesCompatible: Double = 10.0
        var learnedPatternBonus: Double = 30.0

        // Sign and ordering
        var oppositeSignBonus: Double = 15.0
        var correctOrderingBonus: Double = 8.0
        var roundNumberBonus: Double = 5.0

        // Penalties
        var hoursBetweenPenalty: Double = -0.3  // per hour beyond 168 (1 week)
        var rejectedPatternPenalty: Double = -25.0
        var recentRejectionPenalty: Double = -15.0
    }

    private var weights = Weights()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Score a potential transfer match
    func scoreMatch(
        _ features: TransferMatcher.TransferFeatures,
        patterns: [TransferPattern]
    ) -> Double {
        var score: Double = 0.0

        // Amount scoring
        switch features.amountMatch {
        case .exact:
            score += weights.amountExactMatch
        case .feeAdjusted(let fee):
            let feeRatio = min(abs(fee), 10) / 10.0
            score += weights.amountFeeAdjusted * (1.0 - Double(truncating: feeRatio as NSNumber))
        case .close(let diff):
            let diffRatio = min(abs(diff), 100) / 100.0
            score += weights.amountClose * (1.0 - Double(truncating: diffRatio as NSNumber))
        case .different:
            return 0.0  // Not a match
        }

        // Temporal scoring
        if features.withinSameDay {
            score += weights.withinSameDay
        } else if features.hoursBetween <= 168 {  // Within a week
            score += weights.withinWeek * (1.0 - features.hoursBetween / 168.0)
        } else {
            // Penalty for old transactions
            score += weights.hoursBetweenPenalty * (features.hoursBetween - 168)
        }

        // Optimal hours between (peak at 0-24 hours, decay afterward)
        if features.hoursBetween <= 24 {
            score += weights.hoursBetweenOptimal
        } else if features.hoursBetween <= 72 {
            score += weights.hoursBetweenOptimal * (1.0 - (features.hoursBetween - 24) / 48.0)
        }

        // Text similarity scoring
        score += weights.payeeJaccardSimilarity * features.payeeJaccardSimilarity
        score += weights.memoSimilarity * features.memoSimilarity

        if features.hasTransferKeywords {
            score += weights.hasTransferKeywords
        }

        // Account compatibility
        if features.accountTypesCompatible {
            score += weights.accountTypesCompatible
        }

        // Sign and ordering features
        if features.hasOppositeSign {
            score += weights.oppositeSignBonus
        }

        if features.debitCreditOrdering {
            score += weights.correctOrderingBonus
        }

        if features.isRoundNumber {
            score += weights.roundNumberBonus
        }

        // Pattern matching with learned patterns
        if let matchingPattern = findMatchingPattern(features, in: patterns) {
            score += applyPatternBonus(matchingPattern, features: features)
        }

        return max(0, score)
    }

    /// Find the most relevant learned pattern for these features
    private func findMatchingPattern(
        _ features: TransferMatcher.TransferFeatures,
        in patterns: [TransferPattern]
    ) -> TransferPattern? {
        // Filter patterns that match the account pair
        let accountPairPatterns = patterns.filter { pattern in
            pattern.accountPairID == features.accountPairID
        }

        // Find patterns that match the criteria
        for pattern in accountPairPatterns.sorted(by: { $0.confidence > $1.confidence }) {
            if matchesPattern(features, pattern: pattern) {
                return pattern
            }
        }

        return nil
    }

    /// Check if features match a learned pattern
    private func matchesPattern(
        _ features: TransferMatcher.TransferFeatures,
        pattern: TransferPattern
    ) -> Bool {
        // Check amount range
        if let amountRange = pattern.amountRange {
            let amount = abs(features.transaction1.amount)
            if !amountRange.contains(amount) && !amountRange.contains(abs(features.transaction2.amount)) {
                return false
            }
        }

        // Check hours between range
        if let hoursRange = pattern.hoursBetweenRange {
            if !hoursRange.contains(features.hoursBetween) {
                return false
            }
        }

        // Check payee patterns
        if !pattern.commonPayeePatterns.isEmpty {
            let payee1 = features.transaction1.payee.lowercased()
            let payee2 = features.transaction2.payee.lowercased()

            let matchesAnyPattern = pattern.commonPayeePatterns.contains { payeePattern in
                payee1.contains(payeePattern.lowercased()) ||
                payee2.contains(payeePattern.lowercased())
            }

            if !matchesAnyPattern {
                return false
            }
        }

        return true
    }

    /// Apply bonus/penalty based on pattern history
    private func applyPatternBonus(
        _ pattern: TransferPattern,
        features: TransferMatcher.TransferFeatures
    ) -> Double {
        var bonus: Double = 0.0

        // Base bonus from pattern confidence
        bonus += weights.learnedPatternBonus * pattern.confidence

        // Additional bonus for frequently used patterns
        if pattern.useCount > 10 {
            bonus += Double(min(pattern.useCount, 50)) * 0.5
        }

        // Bonus for auto-detected patterns
        if pattern.autoDetectedCount > 0 {
            bonus += Double(pattern.autoDetectedCount) * 2.0
        }

        // Penalty for recently rejected patterns
        if let lastRejection = pattern.lastRejectionDate {
            let daysSinceRejection = -lastRejection.timeIntervalSinceNow / (24 * 3600)
            if daysSinceRejection < 7 {  // Within last week
                bonus += weights.recentRejectionPenalty * (1.0 - daysSinceRejection / 7.0)
            }
        }

        // Penalty if pattern has many rejections
        if pattern.rejectedMatches > pattern.successfulMatches {
            bonus += weights.rejectedPatternPenalty
        }

        return bonus
    }

    /// Determine confidence threshold for auto-linking
    func confidenceThreshold(for pattern: TransferPattern?) -> Double {
        guard let pattern else { return 85.0 }  // High threshold without pattern

        // Lower threshold for reliable patterns
        if pattern.isReliable && pattern.autoDetectedCount > 5 {
            return 70.0
        } else if pattern.confidence > 0.8 {
            return 75.0
        } else {
            return 85.0
        }
    }

    /// Simple online learning: adjust weights based on feedback
    func updateWeightsFromFeedback(_ feedback: TransferFeedback) {
        // This could be enhanced with gradient descent or other learning algorithms
        // For now, we rely on pattern learning in TransferPatternLearner
    }
}

/// Feedback from user actions on transfer suggestions
struct TransferFeedback {
    let features: TransferMatcher.TransferFeatures
    let wasConfirmed: Bool
    let wasAutoDetected: Bool
    let pattern: TransferPattern?
    let timestamp: Date

    init(
        features: TransferMatcher.TransferFeatures,
        wasConfirmed: Bool,
        wasAutoDetected: Bool,
        pattern: TransferPattern? = nil
    ) {
        self.features = features
        self.wasConfirmed = wasConfirmed
        self.wasAutoDetected = wasAutoDetected
        self.pattern = pattern
        self.timestamp = Date()
    }
}
