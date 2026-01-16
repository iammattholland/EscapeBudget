import Foundation
import SwiftData

@Model
final class ReceiptImage {
    var id: UUID
    var createdDate: Date
    var imageData: Data? // Compressed thumbnail (max 100 KB)
    var extractedText: String? // Full OCR text
    var items: [ReceiptItem] // Parsed line items
    var totalAmount: Decimal?
    var merchant: String?
    var receiptDate: Date?
    var isDemoData: Bool

    // Relationship
    var transaction: Transaction?

    init(
        id: UUID = UUID(),
        createdDate: Date = Date(),
        imageData: Data? = nil,
        extractedText: String? = nil,
        items: [ReceiptItem] = [],
        totalAmount: Decimal? = nil,
        merchant: String? = nil,
        receiptDate: Date? = nil,
        isDemoData: Bool = false
    ) {
        self.id = id
        self.createdDate = createdDate
        self.imageData = imageData
        self.extractedText = extractedText
        self.items = items
        self.totalAmount = totalAmount
        self.merchant = merchant
        self.receiptDate = receiptDate
        self.isDemoData = isDemoData
    }
}

// MARK: - Receipt Item

struct ReceiptItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var price: Decimal
    var quantity: Int

    init(id: UUID = UUID(), name: String, price: Decimal, quantity: Int = 1) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}
