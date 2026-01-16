import Foundation

struct PurchasedItemsCSVCodec {
    struct PayloadItem: Codable {
        var name: String
        var price: String
        var note: String?
    }

    static func encode(_ items: [PurchasedItem]?) -> String? {
        let items = (items ?? [])
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        guard !items.isEmpty else { return nil }

        let payload: [PayloadItem] = items.map { item in
            PayloadItem(
                name: item.name,
                price: NSDecimalNumber(decimal: item.price).stringValue,
                note: item.note
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func decode(_ json: String?) -> [PayloadItem] {
        let trimmed = (json ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PayloadItem].self, from: data)) ?? []
    }
}

