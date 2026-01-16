import Foundation
import SwiftData

@MainActor
enum TransactionQueryService {
    struct FetchWindow: Equatable {
        var monthsBack: Int = 12
    }

    // MARK: - Search / Filter semantics

    static func matchesSearch(_ transaction: Transaction, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        if transaction.payee.localizedCaseInsensitiveContains(needle) { return true }
        if (transaction.memo?.localizedCaseInsensitiveContains(needle) ?? false) { return true }
        if transaction.amount.formatted().contains(needle) { return true }
        if (transaction.account?.name.localizedCaseInsensitiveContains(needle) ?? false) { return true }
        if (transaction.category?.name.localizedCaseInsensitiveContains(needle) ?? false) { return true }
        if ((transaction.tags ?? []).contains { $0.name.localizedCaseInsensitiveContains(needle) }) { return true }
        if ((transaction.purchasedItems ?? []).contains {
            $0.name.localizedCaseInsensitiveContains(needle) ||
            ($0.note?.localizedCaseInsensitiveContains(needle) ?? false)
        }) { return true }

        return false
    }

    static func matchesFilter(_ transaction: Transaction, filter: TransactionFilter) -> Bool {
        guard filter.isActive else { return true }

        if filter.useDateRange {
            if transaction.date < filter.startDate || transaction.date > filter.endDate { return false }
        }

        if !filter.payeeName.isEmpty {
            if !transaction.payee.localizedCaseInsensitiveContains(filter.payeeName) { return false }
        }

        if let min = Decimal(string: filter.minAmount) {
            if abs(transaction.amount) < min { return false }
        }

        if let max = Decimal(string: filter.maxAmount) {
            if abs(transaction.amount) > max { return false }
        }

        if let account = filter.account {
            if transaction.account != account { return false }
        }

        if !filter.selectedCategoryIDs.isEmpty || filter.includeUncategorized || filter.includeIgnored {
            let categoryMatch: Bool = {
                if filter.includeIgnored, transaction.kind == .ignored {
                    return true
                }

                guard transaction.kind == .standard else { return false }

                if filter.includeUncategorized, transaction.category == nil {
                    return true
                }

                if let category = transaction.category {
                    return filter.selectedCategoryIDs.contains(category.persistentModelID)
                }

                return false
            }()

            guard categoryMatch else { return false }
        }

        if !filter.tags.isEmpty {
            let txTags = transaction.tags ?? []
            let filterIDs = Set(filter.tags.map(\.persistentModelID))
            if !txTags.contains(where: { filterIDs.contains($0.persistentModelID) }) {
                return false
            }
        }

        return true
    }

    // MARK: - Fetch helpers

    static func cutoffDate(for window: FetchWindow, now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .month, value: -max(1, window.monthsBack), to: now) ?? now
    }

    static func fetchTransactionsPage(
        modelContext: ModelContext,
        offset: Int,
        limit: Int
    ) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    static func fetchTransactions(
        modelContext: ModelContext,
        start: Date,
        end: Date,
        kindRawValue: String? = nil,
        requiresCategory: Bool? = nil
    ) throws -> [Transaction] {
        let sort = [SortDescriptor(\Transaction.date, order: .reverse)]

        if let kindRawValue, let requiresCategory {
            let kind = kindRawValue
            if requiresCategory {
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.date >= start &&
                        tx.date <= end &&
                        tx.kindRawValue == kind &&
                        tx.category != nil
                    },
                    sortBy: sort
                )
                return try modelContext.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.date >= start &&
                        tx.date <= end &&
                        tx.kindRawValue == kind &&
                        tx.category == nil
                    },
                    sortBy: sort
                )
                return try modelContext.fetch(descriptor)
            }
        }

        if let kindRawValue {
            let kind = kindRawValue
            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.date >= start &&
                    tx.date <= end &&
                    tx.kindRawValue == kind
                },
                sortBy: sort
            )
            return try modelContext.fetch(descriptor)
        }

        if let requiresCategory {
            if requiresCategory {
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.date >= start &&
                        tx.date <= end &&
                        tx.category != nil
                    },
                    sortBy: sort
                )
                return try modelContext.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.date >= start &&
                        tx.date <= end &&
                        tx.category == nil
                    },
                    sortBy: sort
                )
                return try modelContext.fetch(descriptor)
            }
        }

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.date >= start &&
                tx.date <= end
            },
            sortBy: sort
        )
        return try modelContext.fetch(descriptor)
    }

    static func fetchTransactionsSince(
        modelContext: ModelContext,
        since: Date
    ) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.date >= since
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    static func fetchRecentPayees(modelContext: ModelContext, limit: Int = 500, fromTransactions: Int = 2500) throws -> [String] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, fromTransactions)
        let txs = try modelContext.fetch(descriptor)

        var seen = Set<String>()
        var payees: [String] = []
        payees.reserveCapacity(min(limit, txs.count))

        for tx in txs {
            let trimmed = tx.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            payees.append(trimmed)
            if payees.count >= limit { break }
        }

        return payees
    }

    // MARK: - Transfer suggestions caching

    private struct TransferSuggestionsCacheEntry {
        var computedAt: Date
        var config: TransferMatcher.Config
        var suggestions: [TransferMatcher.Suggestion]
    }

    private static var transferSuggestionsCache: [ObjectIdentifier: TransferSuggestionsCacheEntry] = [:]
    private static let transferSuggestionCacheTTL: TimeInterval = 15 // seconds

    static func transferSuggestions(
        modelContext: ModelContext
    ) -> [TransferMatcher.Suggestion] {
        transferSuggestions(modelContext: modelContext, config: TransferMatcher.Config())
    }

    static func transferSuggestions(
        modelContext: ModelContext,
        config: TransferMatcher.Config
    ) -> [TransferMatcher.Suggestion] {
        let contextKey = ObjectIdentifier(modelContext)
        let now = Date()

        if let cached = transferSuggestionsCache[contextKey],
           cached.config == config,
           now.timeIntervalSince(cached.computedAt) < transferSuggestionCacheTTL {
            return cached.suggestions
        }

        let computed = TransferMatcher.suggestions(modelContext: modelContext, config: config)
        transferSuggestionsCache[contextKey] = TransferSuggestionsCacheEntry(
            computedAt: now,
            config: config,
            suggestions: computed
        )
        return computed
    }
}
