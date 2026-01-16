import Foundation
import SwiftData

/// ML-based duplicate transaction detection service
@MainActor
final class DuplicateDetectorML {
    private let modelContext: ModelContext

    struct DuplicateCandidate {
        let transaction1: Transaction
        let transaction2: Transaction
        let similarity: Double
        let reasons: [String]
        let matchType: MatchType

        enum MatchType {
            case exact          // Same amount, payee, date
            case likelyDupe     // High similarity, different accounts possible
            case possibleDupe   // Medium similarity
        }
    }

    struct Config {
        var exactMatchWindow: TimeInterval = 24 * 3600  // 24 hours
        var fuzzyMatchWindow: TimeInterval = 7 * 24 * 3600  // 7 days
        var minSimilarityThreshold: Double = 0.7
        var checkSameAccount: Bool = false  // Allow duplicates across accounts

        nonisolated init(exactMatchWindow: TimeInterval = 24 * 3600, fuzzyMatchWindow: TimeInterval = 7 * 24 * 3600, minSimilarityThreshold: Double = 0.7, checkSameAccount: Bool = false) {
            self.exactMatchWindow = exactMatchWindow
            self.fuzzyMatchWindow = fuzzyMatchWindow
            self.minSimilarityThreshold = minSimilarityThreshold
            self.checkSameAccount = checkSameAccount
        }
    }

    private let config: Config

    init(modelContext: ModelContext, config: Config = Config()) {
        self.modelContext = modelContext
        self.config = config
    }

    /// Find potential duplicates for a transaction
    func findDuplicates(for transaction: Transaction, limit: Int = 10) -> [DuplicateCandidate] {
        guard transaction.kind == .standard else { return [] }

        // Fetch transactions within time window
        let startDate = transaction.date.addingTimeInterval(-config.fuzzyMatchWindow)
        let endDate = transaction.date.addingTimeInterval(config.fuzzyMatchWindow)
        let txID = transaction.persistentModelID

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.date >= startDate &&
                tx.date <= endDate &&
                tx.persistentModelID != txID
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allCandidates = try? modelContext.fetch(descriptor) else { return [] }
        let candidates = allCandidates.filter { $0.kind == .standard }

        var duplicates: [DuplicateCandidate] = []

        for candidate in candidates {
            // Skip if same account check is enabled and accounts differ
            if config.checkSameAccount {
                if transaction.account?.persistentModelID != candidate.account?.persistentModelID {
                    continue
                }
            }

            let (similarity, reasons, matchType) = calculateSimilarity(transaction, candidate)

            if similarity >= config.minSimilarityThreshold {
                duplicates.append(DuplicateCandidate(
                    transaction1: transaction,
                    transaction2: candidate,
                    similarity: similarity,
                    reasons: reasons,
                    matchType: matchType
                ))
            }
        }

        return duplicates
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    /// Find all potential duplicates in recent transactions
    func findAllDuplicates(dayRange: Int = 30, limit: Int = 100) -> [DuplicateCandidate] {
        let startDate = Calendar.current.date(byAdding: .day, value: -dayRange, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allTransactions = try? modelContext.fetch(descriptor) else { return [] }
        let transactions = allTransactions.filter { $0.kind == .standard }

        var allDuplicates: [DuplicateCandidate] = []
        var processedPairs = Set<String>()

        for (index, transaction) in transactions.enumerated() {
            // Only check against transactions that come after
            for candidate in transactions.dropFirst(index + 1) {
                let pairID = makePairID(transaction, candidate)
                guard !processedPairs.contains(pairID) else { continue }
                processedPairs.insert(pairID)

                // Check time window
                let timeDiff = abs(transaction.date.timeIntervalSince(candidate.date))
                guard timeDiff <= config.fuzzyMatchWindow else { continue }

                // Skip if same account check is enabled and accounts differ
                if config.checkSameAccount {
                    if transaction.account?.persistentModelID != candidate.account?.persistentModelID {
                        continue
                    }
                }

                let (similarity, reasons, matchType) = calculateSimilarity(transaction, candidate)

                if similarity >= config.minSimilarityThreshold {
                    allDuplicates.append(DuplicateCandidate(
                        transaction1: transaction,
                        transaction2: candidate,
                        similarity: similarity,
                        reasons: reasons,
                        matchType: matchType
                    ))

                    if allDuplicates.count >= limit {
                        return allDuplicates.sorted { $0.similarity > $1.similarity }
                    }
                }
            }
        }

        return allDuplicates.sorted { $0.similarity > $1.similarity }
    }

    // MARK: - Private Methods

    private func calculateSimilarity(
        _ tx1: Transaction,
        _ tx2: Transaction
    ) -> (similarity: Double, reasons: [String], matchType: DuplicateCandidate.MatchType) {

        var score = 0.0
        var reasons: [String] = []

        // 1. Amount matching (40 points max)
        let amount1 = abs(tx1.amount)
        let amount2 = abs(tx2.amount)

        if amount1 == amount2 {
            score += 40.0
            reasons.append("identical amount")
        } else {
            let diff = abs(amount1 - amount2)
            let percentDiff = NSDecimalNumber(decimal: diff / max(amount1, amount2)).doubleValue

            if percentDiff < 0.01 {  // Within 1%
                score += 35.0
                reasons.append("nearly identical amount")
            } else if percentDiff < 0.05 {  // Within 5%
                score += 25.0
                reasons.append("similar amount")
            }
        }

        // 2. Payee matching (30 points max)
        let payee1 = tx1.payee.lowercased()
        let payee2 = tx2.payee.lowercased()

        if payee1 == payee2 {
            score += 30.0
            reasons.append("identical payee")
        } else {
            let distance = levenshteinDistance(payee1, payee2)
            let maxLen = max(payee1.count, payee2.count)
            let similarity = 1.0 - (Double(distance) / Double(max(maxLen, 1)))

            if similarity >= 0.9 {
                score += 25.0
                reasons.append("very similar payee")
            } else if similarity >= 0.7 {
                score += 15.0
                reasons.append("similar payee")
            }
        }

        // 3. Date proximity (20 points max)
        let timeDiff = abs(tx1.date.timeIntervalSince(tx2.date))
        let hoursDiff = timeDiff / 3600.0

        if hoursDiff <= 1 {
            score += 20.0
            reasons.append("within 1 hour")
        } else if hoursDiff <= 24 {
            score += 15.0
            reasons.append("same day")
        } else if hoursDiff <= 72 {
            score += 10.0
            reasons.append("within 3 days")
        } else if hoursDiff <= 168 {
            score += 5.0
            reasons.append("within a week")
        }

        // 4. Memo similarity (10 points max)
        if let memo1 = tx1.memo, let memo2 = tx2.memo,
           !memo1.isEmpty && !memo2.isEmpty {
            let memoDistance = levenshteinDistance(memo1.lowercased(), memo2.lowercased())
            let memoMaxLen = max(memo1.count, memo2.count)
            let memoSimilarity = 1.0 - (Double(memoDistance) / Double(max(memoMaxLen, 1)))

            if memoSimilarity >= 0.8 {
                score += 10.0
                reasons.append("similar memo")
            } else if memoSimilarity >= 0.5 {
                score += 5.0
            }
        }

        // Determine match type
        let normalizedScore = score / 100.0  // Convert to 0-1 scale
        let matchType: DuplicateCandidate.MatchType

        if normalizedScore >= 0.95 {
            matchType = .exact
        } else if normalizedScore >= 0.8 {
            matchType = .likelyDupe
        } else {
            matchType = .possibleDupe
        }

        return (normalizedScore, reasons, matchType)
    }

    private func makePairID(_ tx1: Transaction, _ tx2: Transaction) -> String {
        let id1 = tx1.persistentModelID.hashValue
        let id2 = tx2.persistentModelID.hashValue
        return "\(min(id1, id2))-\(max(id1, id2))"
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = Array(repeating: 0, count: s2.count + 1)
        var matrix = Array(repeating: empty, count: s1.count + 1)

        for i in 0...s1.count {
            matrix[i][0] = i
        }
        for j in 0...s2.count {
            matrix[0][j] = j
        }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[s1.count][s2.count]
    }
}
