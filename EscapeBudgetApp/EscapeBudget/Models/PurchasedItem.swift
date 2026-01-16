import Foundation
import SwiftData

@Model
final class PurchasedItem: DemoDataTrackable {
    var name: String
    var price: Decimal
    var note: String?
    var order: Int
    var createdAt: Date
    var isDemoData: Bool = false

    @Relationship(inverse: \Transaction.purchasedItems)
    var transaction: Transaction?

    init(
        name: String,
        price: Decimal,
        note: String? = nil,
        order: Int = 0,
        createdAt: Date = Date(),
        transaction: Transaction? = nil,
        isDemoData: Bool = false
    ) {
        self.name = name
        self.price = price
        self.note = note
        self.order = order
        self.createdAt = createdAt
        self.transaction = transaction
        self.isDemoData = isDemoData
    }
}

