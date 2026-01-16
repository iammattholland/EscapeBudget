import Foundation
import SwiftData

@Model
final class RecurringPattern {
    var payeePattern: String
    var category: Category?
    var frequency: RecurringFrequency
    var typicalAmount: Decimal?
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var dayOfMonth: Int?  // For monthly: typical day of month (1-31)
    var dayOfWeek: Int?   // For weekly: typical day of week (1-7)
    var lastDetectedDate: Date?
    var occurrenceCount: Int
    var confidence: Double
    var isActive: Bool

    enum RecurringFrequency: String, Codable {
        case weekly = "Weekly"
        case biweekly = "Bi-weekly"
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"

        var days: Int {
            switch self {
            case .weekly: return 7
            case .biweekly: return 14
            case .monthly: return 30
            case .quarterly: return 90
            case .yearly: return 365
            }
        }

        var tolerance: Int {
            switch self {
            case .weekly: return 2
            case .biweekly: return 3
            case .monthly: return 5
            case .quarterly: return 7
            case .yearly: return 14
            }
        }
    }

    init(payee: String, frequency: RecurringFrequency) {
        self.payeePattern = payee.lowercased()
        self.frequency = frequency
        self.occurrenceCount = 0
        self.confidence = 0.5
        self.isActive = true
    }

    /// Is this pattern reliable?
    var isReliable: Bool {
        confidence >= 0.7 && occurrenceCount >= 3
    }

    /// Predict next occurrence date
    func predictNextDate() -> Date? {
        guard let lastDate = lastDetectedDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: frequency.days, to: lastDate)
    }

    /// Check if a date matches this pattern
    func matchesDate(_ date: Date) -> Bool {
        guard let lastDate = lastDetectedDate else { return false }

        let daysDiff = Calendar.current.dateComponents([.day], from: lastDate, to: date).day ?? 0
        let expectedDays = frequency.days
        let tolerance = frequency.tolerance

        return abs(daysDiff - expectedDays) <= tolerance
    }
}
