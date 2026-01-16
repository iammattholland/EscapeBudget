import Foundation
import SwiftData

@MainActor
enum MonthlyAccountTotalsService {
    static func ensureUpToDate(modelContext: ModelContext) {
        Task { @MainActor in
            await ensureUpToDateAsync(modelContext: modelContext)
        }
    }

    static func rebuildAll(modelContext: ModelContext) {
        Task { @MainActor in
            await rebuildAllAsync(modelContext: modelContext)
        }
    }

    static func ensureUpToDateAsync(modelContext: ModelContext) async {
        // Build once if missing (e.g., after upgrading to a version that introduces this model).
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<MonthlyAccountTotal>())) ?? 0
        guard existingCount == 0 else { return }
        await rebuildAllAsync(modelContext: modelContext)
    }

    static func rebuildAllAsync(modelContext: ModelContext) async {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<MonthlyAccountTotal>())
            for entry in existing { modelContext.delete(entry) }

            let txs = try modelContext.fetch(
                FetchDescriptor<Transaction>(
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            )

            struct Key: Hashable {
                var accountID: PersistentIdentifier
                var monthStart: Date
            }

            struct Aggregate {
                var account: Account
                var total: Decimal
                var count: Int
                var isTrackingOnly: Bool
            }

            let calendar = Calendar.current
            var aggregates: [Key: Aggregate] = [:]
            aggregates.reserveCapacity(max(64, txs.count / 12))

            for (index, tx) in txs.enumerated() {
                guard let account = tx.account else { continue }
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) else { continue }

                let key = Key(accountID: account.persistentModelID, monthStart: monthStart)
                if var existing = aggregates[key] {
                    existing.total += tx.amount
                    existing.count += 1
                    aggregates[key] = existing
                } else {
                    aggregates[key] = Aggregate(
                        account: account,
                        total: tx.amount,
                        count: 1,
                        isTrackingOnly: account.isTrackingOnly
                    )
                }

                if index.isMultiple(of: 750) {
                    await Task.yield()
                }
            }

            let computedAt = Date()
            for (index, item) in aggregates.enumerated() {
                let (key, aggregate) = item
                modelContext.insert(
                    MonthlyAccountTotal(
                        monthStart: key.monthStart,
                        account: aggregate.account,
                        totalAmount: aggregate.total,
                        transactionCount: aggregate.count,
                        isTrackingOnly: aggregate.isTrackingOnly,
                        computedAt: computedAt
                    )
                )

                if index.isMultiple(of: 750) {
                    await Task.yield()
                }
            }

            try modelContext.save()
            DataChangeTracker.bump()
        } catch {
            // If totals can't be built, fail soft; callers should fall back to raw computations.
        }
    }

    static func applyDirtyAccountMonthKeys(modelContext: ModelContext, keys: Set<String>) {
        guard !keys.isEmpty else { return }

        let calendar = Calendar.current

        for key in keys {
            guard let parsed = TransactionStatsUpdateCoordinator.parseAccountMonthKey(key) else { continue }
            let monthStart = parsed.monthStart
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

            guard let account = modelContext.model(for: parsed.accountID) as? Account else {
                continue
            }

            // Fetch by date window, then filter by account ID to keep SwiftData predicates simple.
            let txs: [Transaction] = {
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.date >= monthStart && tx.date < monthEnd
                    }
                )
                let fetched = (try? modelContext.fetch(descriptor)) ?? []
                let accountID = account.persistentModelID
                return fetched.filter { $0.account?.persistentModelID == accountID }
            }()

            let total = txs.reduce(Decimal.zero) { $0 + $1.amount }
            let count = txs.count

            // Find existing entry for (monthStart, account)
            let existingForMonth = (try? modelContext.fetch(
                FetchDescriptor<MonthlyAccountTotal>(
                    predicate: #Predicate<MonthlyAccountTotal> { entry in
                        entry.monthStart == monthStart
                    }
                )
            )) ?? []

            let existing = existingForMonth.first { $0.account?.persistentModelID == account.persistentModelID }

            if count == 0 {
                if let existing {
                    modelContext.delete(existing)
                }
                continue
            }

            if let existing {
                existing.totalAmount = total
                existing.transactionCount = count
                existing.isTrackingOnly = account.isTrackingOnly
                existing.computedAt = Date()
            } else {
                modelContext.insert(
                    MonthlyAccountTotal(
                        monthStart: monthStart,
                        account: account,
                        totalAmount: total,
                        transactionCount: count,
                        isTrackingOnly: account.isTrackingOnly
                    )
                )
            }
        }

        do {
            try modelContext.save()
        } catch {
            // fail soft
        }
    }
}
