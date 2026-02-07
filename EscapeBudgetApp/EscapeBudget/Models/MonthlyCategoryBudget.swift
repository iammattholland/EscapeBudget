import Foundation
import SwiftData

@Model
final class MonthlyCategoryBudget: DemoDataTrackable {
    var monthStart: Date
    var amount: Decimal
    var category: Category?
    var isDemoData: Bool = false

    init(monthStart: Date, amount: Decimal, category: Category? = nil, isDemoData: Bool = false) {
        self.monthStart = monthStart
        self.amount = amount
        self.category = category
        self.isDemoData = isDemoData
    }
}

