import Foundation

/// ML-based scoring model for category prediction
struct CategoryScoringModel {
    var weights: Weights

    struct Weights {
        // Payee matching weights
        var exactPayeeMatch: Double = 100.0
        var payeeWordOverlap: Double = 30.0
        var payeeSubstring: Double = 50.0

        // Pattern confidence bonus
        var learnedPatternBonus: Double = 40.0
        var highConfidenceBonus: Double = 20.0

        // Amount matching weights
        var amountInRange: Double = 15.0
        var amountNearTypical: Double = 10.0

        // Temporal matching weights
        var dayOfWeekMatch: Double = 5.0

        // Memo matching weights
        var memoKeywordMatch: Double = 8.0

        // Penalties
        var transferKeywordPenalty: Double = -50.0
    }

    init(weights: Weights = Weights()) {
        self.weights = weights
    }

    /// Score a transaction against learned category patterns
    /// Returns (score, bestPattern) tuple
    func scoreMatch(
        _ features: CategoryPredictor.CategoryFeatures,
        patterns: [CategoryPattern]
    ) -> (score: Double, pattern: CategoryPattern?) {

        var bestScore = 0.0
        var bestPattern: CategoryPattern? = nil

        for pattern in patterns {
            let score = scoreAgainstPattern(features, pattern: pattern)
            if score > bestScore {
                bestScore = score
                bestPattern = pattern
            }
        }

        return (bestScore, bestPattern)
    }

    func scoreAgainstPattern(
        _ features: CategoryPredictor.CategoryFeatures,
        pattern: CategoryPattern
    ) -> Double {
        var score = 0.0

        // 1. Payee matching
        let payee = features.payee
        let patternPayee = pattern.payeePattern

        if payee == patternPayee {
            score += weights.exactPayeeMatch
        } else if payee.contains(patternPayee) || patternPayee.contains(payee) {
            score += weights.payeeSubstring
        } else {
            // Word overlap
            let patternWords = Set(patternPayee.split(separator: " ").map { String($0) })
            let overlap = features.payeeWords.intersection(patternWords)
            if !overlap.isEmpty {
                let overlapRatio = Double(overlap.count) / Double(max(features.payeeWords.count, patternWords.count))
                score += weights.payeeWordOverlap * overlapRatio
            }
        }

        // 2. Pattern confidence bonus
        score += weights.learnedPatternBonus * pattern.confidence

        if pattern.isReliable {
            score += weights.highConfidenceBonus
        }

        // 3. Amount matching
        if let minAmount = pattern.minAmount, let maxAmount = pattern.maxAmount {
            if features.amount >= minAmount && features.amount <= maxAmount {
                score += weights.amountInRange
            }
        }

        if let typicalAmount = pattern.typicalAmount {
            let diff = abs(features.amount - typicalAmount)
            let percentDiff = NSDecimalNumber(decimal: diff / max(features.amount, typicalAmount)).doubleValue
            if percentDiff < 0.1 {  // Within 10% of typical
                score += weights.amountNearTypical
            }
        }

        // 4. Day of week matching
        if let commonDay = pattern.commonDayOfWeek {
            if features.dayOfWeek == commonDay {
                score += weights.dayOfWeekMatch
            }
        }

        // 5. Memo keyword matching
        if let keywords = pattern.commonMemoKeywords {
            for keyword in keywords {
                if features.memo.contains(keyword) {
                    score += weights.memoKeywordMatch
                    break
                }
            }
        }

        // 6. Transfer keyword penalty
        if features.hasTransferKeywords {
            score += weights.transferKeywordPenalty
        }

        return max(0, score)
    }
}
