import Foundation
import SwiftData

@Model
final class BudgetForecast {
    var category: Category?
    var monthYear: Date  // First day of month
    var predictedSpending: Decimal
    var confidence: Double
    var basedOnMonths: Int
    var createdAt: Date

    // Historical data used for prediction
    var historicalAverage: Decimal?
    var historicalMin: Decimal?
    var historicalMax: Decimal?
    var trend: TrendDirection
    var suggestedBudget: Decimal?

    enum TrendDirection: String, Codable {
        case increasing = "Increasing"
        case decreasing = "Decreasing"
        case stable = "Stable"
    }

    init(category: Category?, monthYear: Date, predictedSpending: Decimal, confidence: Double, basedOnMonths: Int, trend: TrendDirection) {
        self.category = category
        self.monthYear = monthYear
        self.predictedSpending = predictedSpending
        self.confidence = confidence
        self.basedOnMonths = basedOnMonths
        self.createdAt = Date()
        self.trend = trend
    }

    /// Is this forecast reliable?
    var isReliable: Bool {
        confidence >= 0.6 && basedOnMonths >= 3
    }

    /// Variance percentage from predicted to actual
    func calculateVariance(actual: Decimal) -> Double {
        let diff = abs(actual - predictedSpending)
        guard predictedSpending > 0 else { return 0.0 }
        return NSDecimalNumber(decimal: diff / predictedSpending).doubleValue
    }
}
