import Foundation
import SwiftData

enum CategoryGroupType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"
}

enum CategoryBudgetType: String, Codable, CaseIterable, Identifiable {
    case monthlyReset = "monthlyReset"
    case monthlyRollover = "monthlyRollover"
    case lumpSum = "lumpSum"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthlyReset:
            return "Monthly (Resets)"
        case .monthlyRollover:
            return "Monthly (Rollover)"
        case .lumpSum:
            return "Lump Sum (Pool)"
        }
    }

    var detail: String {
        switch self {
        case .monthlyReset:
            return "Budget starts fresh each month. Unused funds do not carry forward."
        case .monthlyRollover:
            return "Unused funds carry forward month to month."
        case .lumpSum:
            return "One balance shared across months until you add more funds."
        }
    }
}

enum CategoryOverspendHandling: String, Codable, CaseIterable, Identifiable {
    case carryNegative = "carryNegative"
    case doNotCarry = "doNotCarry"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carryNegative:
            return "Carry overspending forward"
        case .doNotCarry:
            return "Do not carry overspending"
        }
    }

    var detail: String {
        switch self {
        case .carryNegative:
            return "Next month starts reduced until you budget more."
        case .doNotCarry:
            return "Next month starts at $0 even if you overspent this month."
        }
    }
}

@Model
final class CategoryGroup: DemoDataTrackable {
    var name: String
    var order: Int
    var typeRawValue: String
    @Relationship(deleteRule: .cascade) var categories: [Category]?
    var isDemoData: Bool = false
    
    var type: CategoryGroupType {
        get { CategoryGroupType(rawValue: typeRawValue) ?? .expense }
        set { typeRawValue = newValue.rawValue }
    }
    
    var sortedCategories: [Category] {
        (categories ?? []).sorted { $0.order < $1.order }
    }
    
    init(name: String, order: Int = 0, type: CategoryGroupType = .expense, isDemoData: Bool = false) {
        self.name = name
        self.order = order
        self.typeRawValue = type.rawValue
        self.categories = []
        self.isDemoData = isDemoData
    }
}

@Model
final class Category: DemoDataTrackable {
    var name: String
    var assigned: Decimal
    var activity: Decimal
    var order: Int
    var group: CategoryGroup?
    var transactions: [Transaction]?
    var savingsGoal: SavingsGoal?
    var icon: String?
    var memo: String?
    var budgetTypeRawValue: String?
    var overspendHandlingRawValue: String?
    var createdAt: Date?
    var archivedAfterMonthStart: Date?
    var isDemoData: Bool = false

    var budgetType: CategoryBudgetType {
        get { CategoryBudgetType(rawValue: budgetTypeRawValue ?? "") ?? .monthlyReset }
        set { budgetTypeRawValue = newValue.rawValue }
    }

    var overspendHandling: CategoryOverspendHandling {
        get { CategoryOverspendHandling(rawValue: overspendHandlingRawValue ?? "") ?? .carryNegative }
        set { overspendHandlingRawValue = newValue.rawValue }
    }

    func isActive(inMonthStart monthStart: Date, calendar: Calendar = .current) -> Bool {
        if let createdAt {
            let createdMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: createdAt)) ?? createdAt
            if monthStart < createdMonth { return false }
        }
        if let archivedAfterMonthStart {
            return monthStart <= archivedAfterMonthStart
        }
        return true
    }
    
    var available: Decimal {
        assigned - activity
    }
    
    init(name: String, assigned: Decimal = 0.0, activity: Decimal = 0.0, order: Int = 0, icon: String? = nil, memo: String? = nil, isDemoData: Bool = false) {
        self.name = name
        self.assigned = assigned
        self.activity = activity
        self.order = order
        self.icon = icon
        self.memo = memo
        self.budgetTypeRawValue = nil
        self.overspendHandlingRawValue = nil
        self.createdAt = Date()
        self.archivedAfterMonthStart = nil
        self.isDemoData = isDemoData
    }
}
