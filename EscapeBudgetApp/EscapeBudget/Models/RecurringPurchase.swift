import Foundation
import SwiftData

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case weekly = "Weekly"
    case biweekly = "Bi-weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
}

@Model
final class RecurringPurchase: DemoDataTrackable {
    var name: String
    var amount: Decimal
    var frequency: String  // RecurrenceFrequency rawValue
    var nextDate: Date
    var category: String
    var notes: String?
    var isActive: Bool
    var createdDate: Date
    var isDemoData: Bool = false
    
    var recurrenceFrequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequency) ?? .monthly }
        set { frequency = newValue.rawValue }
    }
    
    init(
        name: String,
        amount: Decimal,
        frequency: RecurrenceFrequency,
        nextDate: Date,
        category: String,
        notes: String? = nil,
        isActive: Bool = true,
        isDemoData: Bool = false
    ) {
        self.name = name
        self.amount = amount
        self.frequency = frequency.rawValue
        self.nextDate = nextDate
        self.category = category
        self.notes = notes
        self.isActive = isActive
        self.createdDate = Date()
        self.isDemoData = isDemoData
    }
    
    func calculateNextOccurrence() -> Date {
        let calendar = Calendar.current
        switch recurrenceFrequency {
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: nextDate) ?? nextDate
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: nextDate) ?? nextDate
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: nextDate) ?? nextDate
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: nextDate) ?? nextDate
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: nextDate) ?? nextDate
        }
    }
}
