import Foundation
import SwiftData

@MainActor
enum TransactionHistoryService {
    static func append(
        detail: String,
        to transaction: Transaction,
        in modelContext: ModelContext,
        timestamp: Date = Date(),
        maxEntries: Int? = nil
    ) {
        let entry = TransactionHistoryEntry(
            timestamp: timestamp,
            detail: TransactionTextLimits.normalizedHistoryDetail(detail),
            transaction: transaction
        )
        modelContext.insert(entry)
        trimOldEntries(
            for: transaction,
            in: modelContext,
            keeping: maxEntries ?? TransactionTextLimits.maxHistoryEntriesPerTransaction
        )
    }

    static func trimOldEntries(for transaction: Transaction, in modelContext: ModelContext, keeping keepCount: Int) {
        guard keepCount > 0 else { return }
        guard let entries = transaction.historyEntries, entries.count > keepCount else { return }

        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        for entry in sorted.dropFirst(keepCount) {
            modelContext.delete(entry)
        }
    }
}
