import Foundation
import SwiftData

@MainActor
enum MonthlyCashflowTotalsService {
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
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<MonthlyCashflowTotal>())) ?? 0
        guard existingCount == 0 else { return }
        await rebuildAllAsync(modelContext: modelContext)
    }

    static func rebuildAllAsync(modelContext: ModelContext) async {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<MonthlyCashflowTotal>())
            for entry in existing { modelContext.delete(entry) }

            let standardRaw = TransactionKind.standard.rawValue
            let txs = try modelContext.fetch(
                FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.kindRawValue == standardRaw
                    },
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            )

            struct Aggregate {
                var income: Decimal
                var expense: Decimal
                var count: Int
            }

            let calendar = Calendar.current
            var aggregates: [Date: Aggregate] = [:]
            aggregates.reserveCapacity(max(24, txs.count / 40))

            for (index, tx) in txs.enumerated() {
                guard tx.account?.isTrackingOnly != true else { continue }
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) else { continue }

                var current = aggregates[monthStart] ?? Aggregate(income: 0, expense: 0, count: 0)
                current.count += 1

                if tx.amount > 0, tx.category?.group?.type == .income {
                    current.income += tx.amount
                } else if tx.amount < 0 {
                    current.expense += abs(tx.amount)
                }

                aggregates[monthStart] = current

                if index.isMultiple(of: 750) {
                    await Task.yield()
                }
            }

            let computedAt = Date()
            for (index, item) in aggregates.enumerated() {
                let (monthStart, aggregate) = item
                modelContext.insert(
                    MonthlyCashflowTotal(
                        monthStart: monthStart,
                        incomeTotal: aggregate.income,
                        expenseTotal: aggregate.expense,
                        transactionCount: aggregate.count,
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
            // Fail soft; callers should fall back to raw computations when needed.
        }
    }

    static func applyDirtyMonthKeys(modelContext: ModelContext, monthKeys: Set<String>) {
        guard !monthKeys.isEmpty else { return }

        let calendar = Calendar.current
        let standardRaw = TransactionKind.standard.rawValue

        for key in monthKeys {
            guard let monthStart = TransactionStatsUpdateCoordinator.parseMonthKey(key) else { continue }
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.kindRawValue == standardRaw &&
                    tx.date >= monthStart &&
                    tx.date < monthEnd
                }
            )
            let fetched = (try? modelContext.fetch(descriptor)) ?? []
            let txs = fetched.filter { $0.account?.isTrackingOnly != true }

            var income: Decimal = 0
            var expense: Decimal = 0
            for tx in txs {
                if tx.amount > 0, tx.category?.group?.type == .income {
                    income += tx.amount
                } else if tx.amount < 0 {
                    expense += abs(tx.amount)
                }
            }

            let count = txs.count

            let existing = (try? modelContext.fetch(
                FetchDescriptor<MonthlyCashflowTotal>(
                    predicate: #Predicate<MonthlyCashflowTotal> { entry in
                        entry.monthStart == monthStart
                    }
                )
            ))?.first

            if count == 0 {
                if let existing {
                    modelContext.delete(existing)
                }
                continue
            }

            if let existing {
                existing.incomeTotal = income
                existing.expenseTotal = expense
                existing.transactionCount = count
                existing.computedAt = Date()
            } else {
                modelContext.insert(
                    MonthlyCashflowTotal(
                        monthStart: monthStart,
                        incomeTotal: income,
                        expenseTotal: expense,
                        transactionCount: count
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
