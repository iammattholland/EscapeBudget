import Foundation
import SwiftData

@Model
final class PayeePattern {
    var canonicalName: String
    var variants: [String]
    var useCount: Int
    var lastUsedAt: Date
    var confidence: Double

    // Learned features
    var merchantType: String?
    var commonCategory: Category?

    init(canonicalName: String, variant: String) {
        self.canonicalName = canonicalName
        self.variants = [variant.lowercased()]
        self.useCount = 1
        self.lastUsedAt = Date()
        self.confidence = 0.5
    }

    /// Check if a payee matches any variant
    func matches(_ payee: String) -> Bool {
        let normalized = payee.lowercased()
        return variants.contains(normalized) ||
               canonicalName.lowercased() == normalized
    }

    /// Add a new variant
    func addVariant(_ variant: String) {
        let normalized = variant.lowercased()
        if !variants.contains(normalized) && normalized != canonicalName.lowercased() {
            variants.append(normalized)
        }
    }

    /// Is this pattern reliable enough to auto-suggest?
    var isReliable: Bool {
        confidence >= 0.7 && useCount >= 3
    }
}
