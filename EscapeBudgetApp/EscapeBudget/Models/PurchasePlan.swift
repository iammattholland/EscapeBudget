import Foundation
import SwiftData

@Model
final class PurchasePlan: DemoDataTrackable {
    var itemName: String
    var expectedPrice: Decimal
    var purchaseDate: Date?
    var url: String?
    var category: String
    var priority: Int  // 1-5 scale
    var notes: String?
    var imageData: Data?
    var isPurchased: Bool
    var actualPrice: Decimal?
    var actualPurchaseDate: Date?
    var createdDate: Date
    var isDemoData: Bool = false
    
    init(
        itemName: String,
        expectedPrice: Decimal,
        purchaseDate: Date? = nil,
        url: String? = nil,
        category: String = "Other",
        priority: Int = 3,
        notes: String? = nil,
        imageData: Data? = nil,
        isPurchased: Bool = false,
        actualPrice: Decimal? = nil,
        actualPurchaseDate: Date? = nil,
        isDemoData: Bool = false
    ) {
        self.itemName = itemName
        self.expectedPrice = expectedPrice
        self.purchaseDate = purchaseDate
        self.url = url
        self.category = category
        self.priority = priority
        self.notes = notes
        self.imageData = imageData
        self.isPurchased = isPurchased
        self.actualPrice = actualPrice
        self.actualPurchaseDate = actualPurchaseDate
        self.createdDate = Date()
        self.isDemoData = isDemoData
    }

    /// Returns a validated URL if the stored URL string is safe to open.
    /// Only allows http and https schemes to prevent javascript:, file:, or other dangerous URLs.
    var validatedURL: URL? {
        guard let urlString = url,
              !urlString.isEmpty,
              let parsedURL = URL(string: urlString),
              let scheme = parsedURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme) else {
            return nil
        }
        return parsedURL
    }

    /// Checks if the stored URL is valid and safe to open
    var hasValidURL: Bool {
        validatedURL != nil
    }

    static let categories = ["Electronics", "Home", "Auto", "Clothing", "Travel", "Other"]
}
