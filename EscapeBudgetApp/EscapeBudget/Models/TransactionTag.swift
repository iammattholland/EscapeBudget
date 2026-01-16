import Foundation
import SwiftData

@Model
final class TransactionTag: DemoDataTrackable {
    var name: String
    /// Hex string like "#FF9500"
    var colorHex: String
    /// User-defined ordering for tag lists
    var order: Int
    var isDemoData: Bool = false

    @Relationship(inverse: \Transaction.tags)
    var transactions: [Transaction]?

    init(name: String, colorHex: String, order: Int = 0, isDemoData: Bool = false) {
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.isDemoData = isDemoData
    }
}
