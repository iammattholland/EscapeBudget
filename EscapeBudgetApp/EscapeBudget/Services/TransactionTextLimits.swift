import Foundation

enum TransactionTextLimits {
    nonisolated static let maxMemoLength = 500
    nonisolated static let maxHistoryDetailLength = 300
    nonisolated static let maxHistoryEntriesPerTransaction = 200
    nonisolated static let maxPurchasedItemsPerTransaction = 150
    nonisolated static let maxPurchasedItemNameLength = 120
    nonisolated static let maxPurchasedItemNoteLength = 500

    nonisolated static func normalizedMemo(_ memo: String?) -> String? {
        guard let memo else { return nil }
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncate(trimmed, max: maxMemoLength)
    }

    nonisolated static func normalizedHistoryDetail(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Update" }
        return truncate(trimmed, max: maxHistoryDetailLength)
    }

    nonisolated static func normalizedPurchasedItemName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Item" }
        return truncate(trimmed, max: maxPurchasedItemNameLength)
    }

    nonisolated static func normalizedPurchasedItemNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncate(trimmed, max: maxPurchasedItemNoteLength)
    }

    nonisolated private static func truncate(_ string: String, max: Int) -> String {
        guard string.count > max else { return string }
        return String(string.prefix(max - 1)) + "…"
    }
}
