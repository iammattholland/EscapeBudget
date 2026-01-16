import Foundation
import SwiftData

enum CategoryGroupType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"
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
    var isDemoData: Bool = false
    
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
        self.isDemoData = isDemoData
    }
}
