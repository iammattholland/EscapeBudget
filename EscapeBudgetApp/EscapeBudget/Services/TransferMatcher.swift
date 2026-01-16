import Foundation
import SwiftData

enum TransferMatcher {
    struct Suggestion: Identifiable, Equatable {
        let baseID: PersistentIdentifier
        let matchID: PersistentIdentifier
        let amount: Decimal
        let score: Double
        let daysApart: Int
        let matchedPattern: TransferPattern?  // Pattern that matched, if any

        var id: String { "\(String(describing: baseID))|\(String(describing: matchID))" }
    }

    struct Config: Equatable {
        var lookbackDays: Int = 90
        var maxDaysApart: Int = 7
        var limit: Int = 50
        var minScore: Double = 0.55
        var useMLScoring: Bool = true  // Enable ML-based scoring
        var maxAmountDifferenceCents: Int = 0  // Allow matching with small amount differences (fees/rounding)

        nonisolated init(
            lookbackDays: Int = 90,
            maxDaysApart: Int = 7,
            limit: Int = 50,
            minScore: Double = 0.55,
            useMLScoring: Bool = true,
            maxAmountDifferenceCents: Int = 0
        ) {
            self.lookbackDays = lookbackDays
            self.maxDaysApart = maxDaysApart
            self.limit = limit
            self.minScore = minScore
            self.useMLScoring = useMLScoring
            self.maxAmountDifferenceCents = maxAmountDifferenceCents
        }
    }

    @MainActor
    static func suggestions(modelContext: ModelContext) -> [Suggestion] {
        suggestions(modelContext: modelContext, config: Config())
    }

    @MainActor
    static func suggestions(modelContext: ModelContext, config: Config) -> [Suggestion] {
        let now = Date()
        let lookbackStart = Calendar.current.date(byAdding: .day, value: -max(1, config.lookbackDays), to: now) ?? now

        let standardRaw = TransactionKind.standard.rawValue
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.transferID == nil &&
                t.transferInboxDismissed == false &&
                t.kindRawValue == standardRaw &&
                t.date >= lookbackStart
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )

        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let eligible = candidates.filter { $0.account != nil && $0.amount != 0 }

        // Load learned patterns if ML scoring is enabled
        let patterns = config.useMLScoring ? TransferPatternLearner(modelContext: modelContext).fetchReliablePatterns() : []
        let scoringModel = config.useMLScoring ? TransferScoringModel(modelContext: modelContext) : nil

        let bucketCents = max(1, config.maxAmountDifferenceCents == 0 ? 1 : config.maxAmountDifferenceCents)
        let groups = Dictionary(grouping: eligible, by: { absAmountBucket(for: $0.amount, bucketCents: bucketCents) })
        var results: [Suggestion] = []
        var seen = Set<String>()

        for (_, transactions) in groups {
            let positives = transactions.filter { $0.amount > 0 }
            let negatives = transactions.filter { $0.amount < 0 }
            guard !positives.isEmpty, !negatives.isEmpty else { continue }

            for outflow in negatives {
                for inflow in positives {
                    guard outflow.account?.persistentModelID != inflow.account?.persistentModelID else { continue }

                    if config.maxAmountDifferenceCents > 0 {
                        let deltaCents = absAmountDifferenceCents(outflow.amount, inflow.amount)
                        guard deltaCents <= config.maxAmountDifferenceCents else { continue }
                    }

                    let daysApart = abs(dayDistance(outflow.date, inflow.date))
                    guard daysApart <= config.maxDaysApart else { continue }

                    // Use ML scoring if enabled, otherwise use legacy scoring
                    let (score, matchedPattern): (Double, TransferPattern?)
                    if config.useMLScoring, let scoringModel {
                        let features = TransferFeatures(transaction1: outflow, transaction2: inflow)
                        let mlScore = scoringModel.scoreMatch(features, patterns: patterns) / 100.0  // Normalize to 0-1
                        let pattern = patterns.first { pattern in
                            pattern.accountPairID == features.accountPairID
                        }
                        score = mlScore
                        matchedPattern = pattern
                    } else {
                        score = scorePair(outflow: outflow, inflow: inflow, maxDaysApart: config.maxDaysApart)
                        matchedPattern = nil
                    }

                    guard score >= config.minScore else { continue }

                    let key = pairKey(outflowID: outflow.persistentModelID, inflowID: inflow.persistentModelID)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)

                    results.append(
                        Suggestion(
                            baseID: outflow.persistentModelID,
                            matchID: inflow.persistentModelID,
                            amount: abs(outflow.amount),
                            score: score,
                            daysApart: daysApart,
                            matchedPattern: matchedPattern
                        )
                    )
                }
            }
        }

        return results
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.daysApart != rhs.daysApart { return lhs.daysApart < rhs.daysApart }
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.id < rhs.id
            }
            .prefix(config.limit)
            .map { $0 }
    }

    private static func pairKey(outflowID: PersistentIdentifier, inflowID: PersistentIdentifier) -> String {
        let left = String(describing: outflowID)
        let right = String(describing: inflowID)
        return left < right ? "\(left)|\(right)" : "\(right)|\(left)"
    }

    private static func absAmountKey(for amount: Decimal) -> Int {
        let value = NSDecimalNumber(decimal: abs(amount)).doubleValue
        return Int((value * 100).rounded())
    }

    private static func absAmountBucket(for amount: Decimal, bucketCents: Int) -> Int {
        let cents = absAmountKey(for: amount)
        return cents / max(1, bucketCents)
    }

    private static func absAmountDifferenceCents(_ outflowAmount: Decimal, _ inflowAmount: Decimal) -> Int {
        let a = absAmountKey(for: outflowAmount)
        let b = absAmountKey(for: inflowAmount)
        return abs(a - b)
    }

    private static func dayDistance(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a), to: Calendar.current.startOfDay(for: b)).day ?? 0
    }

    private static func looksTransferish(_ transaction: Transaction) -> Bool {
        let payee = normalize(transaction.payee)
        let memo = normalize(transaction.memo ?? "")
        let text = "\(payee) \(memo)"
        let keywords = ["transfer", "xfer", "payment", "paid", "move", "moved", "card", "credit", "cc", "visa", "mastercard", "amex", "interac", "e-transfer", "etransfer"]
        return keywords.contains(where: { text.contains($0) }) || transaction.category == nil
    }

    private static func isLiabilityAccountType(_ type: AccountType) -> Bool {
        switch type {
        case .creditCard, .lineOfCredit, .mortgage, .loans:
            return true
        case .chequing, .savings, .investment, .other:
            return false
        }
    }

    private static func amountBoost(for amount: Decimal) -> Double {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        guard value >= 50 else { return 0 }
        return min(0.10, log10(value) * 0.03)
    }

    private static func scorePair(outflow: Transaction, inflow: Transaction, maxDaysApart: Int) -> Double {
        var score: Double = 1.0

        let daysApart = Double(abs(dayDistance(outflow.date, inflow.date)))
        let maxDays = Double(max(1, maxDaysApart))
        score -= min(0.45, (daysApart / maxDays) * 0.45)

        score += amountBoost(for: abs(outflow.amount))

        if let outType = outflow.account?.type, let inType = inflow.account?.type {
            if isLiabilityAccountType(outType) != isLiabilityAccountType(inType) {
                score += 0.06
            }
        }

        if looksTransferish(outflow) { score += 0.12 }
        if looksTransferish(inflow) { score += 0.08 }

        if isLikelyCreditCardPayment(outflow: outflow, inflow: inflow) {
            score += 0.18
        }

        if shareToken(outflow.payee, inflow.payee) || shareToken(outflow.memo ?? "", inflow.memo ?? "") {
            score += 0.08
        }

        return max(0, min(1, score))
    }

    private static func isLikelyCreditCardPayment(outflow: Transaction, inflow: Transaction) -> Bool {
        guard let outAccount = outflow.account, let inAccount = inflow.account else { return false }

        // Typical pattern: money leaves chequing/savings and enters a credit card account.
        let outIsBank = (outAccount.type == .chequing || outAccount.type == .savings)
        let inIsCreditCard = (inAccount.type == .creditCard)
        guard outIsBank && inIsCreditCard else { return false }

        // Also accept reverse direction if sign conventions are swapped by bank export.
        let reverseOutIsCC = (outAccount.type == .creditCard)
        let reverseInIsBank = (inAccount.type == .chequing || inAccount.type == .savings)
        if !(outIsBank && inIsCreditCard) && !(reverseOutIsCC && reverseInIsBank) {
            return false
        }

        let text = normalize(outflow.payee + " " + (outflow.memo ?? "") + " " + inflow.payee + " " + (inflow.memo ?? ""))
        let keywords = ["credit card", "cc payment", "visa", "mastercard", "amex", "card payment", "payment to", "payment"]
        return keywords.contains(where: { text.contains($0) })
    }

    private static func normalize(_ string: String) -> String {
        string
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shareToken(_ a: String, _ b: String) -> Bool {
        let leftTokens = Set(normalize(a).split(separator: " ").map(String.init).filter { $0.count >= 3 })
        guard !leftTokens.isEmpty else { return false }
        let rightTokens = Set(normalize(b).split(separator: " ").map(String.init).filter { $0.count >= 3 })
        return !leftTokens.intersection(rightTokens).isEmpty
    }
}
