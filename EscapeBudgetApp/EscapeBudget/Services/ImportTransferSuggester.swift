import Foundation
import SwiftData

enum ImportTransferSuggester {
    struct Suggestion: Identifiable, Equatable {
        let outflowID: UUID
        let inflowID: UUID
        let score: Double
        let daysApart: Int

        var id: String {
            let a = outflowID.uuidString
            let b = inflowID.uuidString
            return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
        }
    }

    struct Config: Equatable {
        var maxDaysApart: Int = 3
        var maxSuggestions: Int = 60
        var minScore: Double = 0.70
    }

    static func suggest(
        transactions: [ImportedTransaction],
        config: Config = Config(),
        eligible: (ImportedTransaction) -> Bool,
        accountIDFor: (ImportedTransaction) -> PersistentIdentifier?,
        transferishHintFor: (ImportedTransaction) -> Bool
    ) -> [Suggestion] {
        let eligibleTx = transactions.filter(eligible)
        guard eligibleTx.count >= 2 else { return [] }

        let grouped = Dictionary(grouping: eligibleTx, by: { absAmountKey(for: $0.amount) })
        var results: [Suggestion] = []
        var seen = Set<String>()

        for (_, group) in grouped {
            let positives = group.filter { $0.amount > 0 }
            let negatives = group.filter { $0.amount < 0 }
            guard !positives.isEmpty, !negatives.isEmpty else { continue }

            for outflow in negatives {
                let outflowAccount = accountIDFor(outflow)
                guard outflowAccount != nil else { continue }

                var best: Suggestion?
                for inflow in positives {
                    let inflowAccount = accountIDFor(inflow)
                    guard inflowAccount != nil else { continue }
                    guard inflowAccount != outflowAccount else { continue }

                    let daysApart = abs(dayDistance(outflow.date, inflow.date))
                    guard daysApart <= config.maxDaysApart else { continue }

                    let score = scorePair(
                        outflow: outflow,
                        inflow: inflow,
                        maxDaysApart: config.maxDaysApart,
                        outflowTransferish: transferishHintFor(outflow),
                        inflowTransferish: transferishHintFor(inflow)
                    )
                    guard score >= config.minScore else { continue }

                    let suggestion = Suggestion(
                        outflowID: outflow.id,
                        inflowID: inflow.id,
                        score: score,
                        daysApart: daysApart
                    )

                    if best == nil || suggestion.score > best!.score {
                        best = suggestion
                    }
                }

                if let best {
                    let key = best.id
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    results.append(best)
                }
            }
        }

        return results
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.daysApart < rhs.daysApart
            }
            .prefix(config.maxSuggestions)
            .map { $0 }
    }

    private static func absAmountKey(for amount: Decimal) -> Int {
        let value = NSDecimalNumber(decimal: abs(amount)).doubleValue
        return Int((value * 100).rounded())
    }

    private static func dayDistance(_ a: Date, _ b: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: a),
            to: calendar.startOfDay(for: b)
        ).day ?? 999
    }

    private static func scorePair(
        outflow: ImportedTransaction,
        inflow: ImportedTransaction,
        maxDaysApart: Int,
        outflowTransferish: Bool,
        inflowTransferish: Bool
    ) -> Double {
        var score: Double = 1.0

        let daysApart = Double(abs(dayDistance(outflow.date, inflow.date)))
        let maxDays = Double(max(1, maxDaysApart))
        score -= min(0.50, (daysApart / maxDays) * 0.50)

        if outflowTransferish { score += 0.12 }
        if inflowTransferish { score += 0.08 }

        if shareToken(outflow.rawPayee ?? outflow.payee, inflow.rawPayee ?? inflow.payee) ||
            shareToken(outflow.memo ?? "", inflow.memo ?? "") {
            score += 0.06
        }

        return max(0, min(1, score))
    }

    private static func normalize(_ string: String) -> String {
        PayeeNormalizer.normalizeForComparison(string)
    }

    private static func shareToken(_ a: String, _ b: String) -> Bool {
        let leftTokens = Set(normalize(a).split(separator: " ").map(String.init).filter { $0.count >= 3 })
        guard !leftTokens.isEmpty else { return false }
        let rightTokens = Set(normalize(b).split(separator: " ").map(String.init).filter { $0.count >= 3 })
        return !leftTokens.intersection(rightTokens).isEmpty
    }
}
