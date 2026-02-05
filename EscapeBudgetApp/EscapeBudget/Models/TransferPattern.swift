import Foundation
import SwiftData

/// Learned patterns for transfer detection based on user confirmations and rejections
@Model
final class TransferPattern {
    var id: UUID
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int

    // Pattern identification
    var accountPairID: String  // "\(fromAccountID)-\(toAccountID)"

    // Learned amount patterns
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var commonFeeAmount: Decimal?  // Common fee difference (e.g., $3 ATM fee)

    // Learned timing patterns
    var minHoursBetween: Double?
    var maxHoursBetween: Double?
    var typicalHoursBetween: Double?

    // Learned text patterns
    var commonPayeePatterns: [String]  // Payee substrings that indicate transfers
    var commonMemoKeywords: [String]?  // Memo keywords

    // Learned calendar patterns
    /// 0 = end-of-month, otherwise day of month (1...31)
    var commonDayOfMonth: Int?
    var dayOfMonthMatchCount: Int
    var dayOfMonthSampleCount: Int

    // Confidence metrics
    var successfulMatches: Int  // User confirmed these matches
    var rejectedMatches: Int     // User rejected these suggestions
    var lastSuccessDate: Date?
    var lastRejectionDate: Date?

    // Performance tracking
    var autoDetectedCount: Int  // How many times this pattern auto-detected correctly
    var manualLinkCount: Int    // How many times user manually linked this pattern

    var isDemoData: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        useCount: Int = 0,
        accountPairID: String,
        successfulMatches: Int = 0,
        rejectedMatches: Int = 0,
        autoDetectedCount: Int = 0,
        manualLinkCount: Int = 0,
        commonPayeePatterns: [String] = [],
        commonDayOfMonth: Int? = nil,
        dayOfMonthMatchCount: Int = 0,
        dayOfMonthSampleCount: Int = 0,
        isDemoData: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.accountPairID = accountPairID
        self.successfulMatches = successfulMatches
        self.rejectedMatches = rejectedMatches
        self.autoDetectedCount = autoDetectedCount
        self.manualLinkCount = manualLinkCount
        self.commonPayeePatterns = commonPayeePatterns
        self.commonDayOfMonth = commonDayOfMonth
        self.dayOfMonthMatchCount = dayOfMonthMatchCount
        self.dayOfMonthSampleCount = dayOfMonthSampleCount
        self.isDemoData = isDemoData
    }

    /// Confidence score (0.0 to 1.0) based on user feedback
    var confidence: Double {
        let total = successfulMatches + rejectedMatches
        guard total > 0 else { return 0.5 }  // Neutral for new patterns

        var baseConfidence = Double(successfulMatches) / Double(total)

        // Boost confidence for frequently used patterns
        if useCount > 10 {
            baseConfidence = min(1.0, baseConfidence * 1.1)
        }

        // Penalize if recently rejected
        if let lastRejection = lastRejectionDate,
           lastRejection.timeIntervalSinceNow > -7 * 24 * 3600 {  // Within last week
            baseConfidence *= 0.8
        }

        return baseConfidence
    }

    /// Whether this pattern is reliable enough to use
    var isReliable: Bool {
        // Need at least 3 successful matches and confidence > 0.7
        return successfulMatches >= 3 && confidence > 0.7
    }

    /// Amount range as a closed range if both bounds exist
    var amountRange: ClosedRange<Decimal>? {
        guard let min = minAmount, let max = maxAmount else { return nil }
        return min...max
    }

    /// Hours between range as a closed range if both bounds exist
    var hoursBetweenRange: ClosedRange<Double>? {
        guard let min = minHoursBetween, let max = maxHoursBetween else { return nil }
        return min...max
    }
}
