import Foundation
import SwiftData

@MainActor
enum StatsSanityChecker {
    static func checkRecentMonths(in modelContext: ModelContext, monthsBack: Int = 3, isDemoData: Bool = false) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        var mismatches: [String] = []

        for offset in 0..<max(1, monthsBack) {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else { continue }
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

            let expected = expectedCashflowTotals(modelContext: modelContext, monthStart: monthStart, monthEnd: monthEnd)
            let stored = storedCashflowTotals(modelContext: modelContext, monthStart: monthStart)

            if stored == nil {
                if expected.count > 0 {
                    mismatches.append("\(isoMonth(monthStart)): missing stored totals")
                }
                continue
            }

            guard let stored else { continue }

            // Tolerate tiny currency rounding noise (Dec <-> Double conversions elsewhere).
            let tolerance: Decimal = 0.01
            if abs(stored.income - expected.income) > tolerance ||
                abs(stored.expense - expected.expense) > tolerance ||
                stored.count != expected.count {
                mismatches.append("\(isoMonth(monthStart)): stored(income=\(stored.income), expense=\(stored.expense), count=\(stored.count)) expected(income=\(expected.income), expense=\(expected.expense), count=\(expected.count))")
            }
        }

        guard !mismatches.isEmpty else { return }

        DiagnosticsService.recordEvent(
            title: "Stats mismatch detected",
            message: "Monthly cashflow totals differ from raw transactions.",
            area: "Stats",
            severity: .warning,
            operation: "sanityCheck",
            context: [
                "mismatches": mismatches.joined(separator: " | ")
            ],
            in: modelContext,
            isDemoData: isDemoData
        )
    }

    private static func expectedCashflowTotals(modelContext: ModelContext, monthStart: Date, monthEnd: Date) -> (income: Decimal, expense: Decimal, count: Int) {
        let standardRaw = TransactionKind.standard.rawValue
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

        return (income, expense, txs.count)
    }

    private static func storedCashflowTotals(modelContext: ModelContext, monthStart: Date) -> (income: Decimal, expense: Decimal, count: Int)? {
        let descriptor = FetchDescriptor<MonthlyCashflowTotal>(
            predicate: #Predicate<MonthlyCashflowTotal> { entry in
                entry.monthStart == monthStart
            }
        )
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return nil }
        return (entry.incomeTotal, entry.expenseTotal, entry.transactionCount)
    }

    private static func isoMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}

