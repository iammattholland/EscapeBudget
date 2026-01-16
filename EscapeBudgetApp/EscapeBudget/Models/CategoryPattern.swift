import Foundation
import SwiftData

@Model
final class CategoryPattern {
    var category: Category?
    var payeePattern: String
    var useCount: Int
    var successfulMatches: Int
    var rejectedMatches: Int
    var lastUsedAt: Date
    var lastSuccessDate: Date?
    var lastRejectionDate: Date?

    // Learned features
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var typicalAmount: Decimal?
    var commonDayOfWeek: Int?
    var commonMemoKeywords: [String]?
    var merchantType: String?

    // Auto-detected vs manual categorization tracking
    var autoDetectedCount: Int
    var manualCategoryCount: Int

    init(category: Category?, payeePattern: String) {
        self.category = category
        self.payeePattern = payeePattern.lowercased()
        self.useCount = 0
        self.successfulMatches = 0
        self.rejectedMatches = 0
        self.lastUsedAt = Date()
        self.autoDetectedCount = 0
        self.manualCategoryCount = 0
    }

    /// Confidence score (0.0 to 1.0) based on success rate and sample size
    var confidence: Double {
        let totalMatches = successfulMatches + rejectedMatches
        guard totalMatches > 0 else { return 0.0 }

        let successRate = Double(successfulMatches) / Double(totalMatches)

        // Require at least 3 successful matches for high confidence
        let sampleSizeFactor = min(1.0, Double(successfulMatches) / 3.0)

        return successRate * sampleSizeFactor
    }

    /// Is this pattern reliable enough to auto-suggest?
    var isReliable: Bool {
        confidence >= 0.7 && successfulMatches >= 3
    }
}
