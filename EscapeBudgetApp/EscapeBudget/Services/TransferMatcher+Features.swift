import Foundation
import SwiftData

extension TransferMatcher {
    /// Features extracted from a pair of transactions for ML-based matching
    struct TransferFeatures {
        // Transaction pair
        let transaction1: Transaction
        let transaction2: Transaction

        // Temporal features
        let hoursBetween: Double
        let dayOfWeekMatch: Bool
        let sameMonth: Bool
        let withinSameDay: Bool

        // Amount features
        let amountMatch: AmountMatchType
        let absoluteAmountDifference: Decimal
        let isRoundNumber: Bool
        let amountSum: Decimal  // Should be close to zero for transfers

        // Text similarity features
        let payeeLevenshteinDistance: Int
        let payeeJaccardSimilarity: Double
        let memoSimilarity: Double
        let hasTransferKeywords: Bool

        // Account features
        let accountPairID: String
        let accountTypesCompatible: Bool  // e.g., checking->savings is common

        // Sign features
        let hasOppositeSign: Bool
        let debitCreditOrdering: Bool  // Debit before credit is common

        enum AmountMatchType {
            case exact
            case feeAdjusted(fee: Decimal)
            case close(difference: Decimal)
            case different
        }

        init(transaction1: Transaction, transaction2: Transaction) {
            self.transaction1 = transaction1
            self.transaction2 = transaction2

            // Calculate temporal features
            let timeDiff = abs(transaction1.date.timeIntervalSince(transaction2.date))
            self.hoursBetween = timeDiff / 3600.0

            let calendar = Calendar.current
            self.dayOfWeekMatch = calendar.component(.weekday, from: transaction1.date) ==
                                   calendar.component(.weekday, from: transaction2.date)
            self.sameMonth = calendar.isDate(transaction1.date, equalTo: transaction2.date, toGranularity: .month)
            self.withinSameDay = calendar.isDate(transaction1.date, equalTo: transaction2.date, toGranularity: .day)

            // Calculate amount features
            let amount1 = abs(transaction1.amount)
            let amount2 = abs(transaction2.amount)
            self.absoluteAmountDifference = abs(amount1 - amount2)
            self.amountSum = transaction1.amount + transaction2.amount

            // Determine amount match type
            if amount1 == amount2 {
                self.amountMatch = .exact
            } else if absoluteAmountDifference <= 10 {  // Within $10 might be a fee
                self.amountMatch = .feeAdjusted(fee: absoluteAmountDifference)
            } else if absoluteAmountDifference / max(amount1, amount2) < 0.05 {  // Within 5%
                self.amountMatch = .close(difference: absoluteAmountDifference)
            } else {
                self.amountMatch = .different
            }

            self.isRoundNumber = Self.isRoundAmount(amount1)

            // Calculate text similarity
            self.payeeLevenshteinDistance = Self.levenshteinDistance(
                transaction1.payee.lowercased(),
                transaction2.payee.lowercased()
            )
            self.payeeJaccardSimilarity = Self.jaccardSimilarity(
                transaction1.payee.lowercased(),
                transaction2.payee.lowercased()
            )

            let memo1 = transaction1.memo?.lowercased() ?? ""
            let memo2 = transaction2.memo?.lowercased() ?? ""
            self.memoSimilarity = Self.jaccardSimilarity(memo1, memo2)

            let transferKeywords = ["transfer", "xfer", "tfr", "atm", "withdrawal", "deposit", "move"]
            self.hasTransferKeywords = transferKeywords.contains { keyword in
                transaction1.payee.lowercased().contains(keyword) ||
                transaction2.payee.lowercased().contains(keyword) ||
                memo1.contains(keyword) || memo2.contains(keyword)
            }

            // Account features
            let account1ID = transaction1.account?.persistentModelID.hashValue ?? 0
            let account2ID = transaction2.account?.persistentModelID.hashValue ?? 0
            self.accountPairID = "\(min(account1ID, account2ID))-\(max(account1ID, account2ID))"

            let type1 = transaction1.account?.type ?? .chequing
            let type2 = transaction2.account?.type ?? .chequing
            self.accountTypesCompatible = Self.areAccountTypesCompatible(type1, type2)

            // Sign features
            self.hasOppositeSign = (transaction1.amount > 0) != (transaction2.amount > 0)
            self.debitCreditOrdering = transaction1.amount < 0 && transaction2.amount > 0 &&
                                        transaction1.date <= transaction2.date
        }

        // MARK: - Helper Methods

        private static func isRoundAmount(_ amount: Decimal) -> Bool {
            let absAmount = abs(amount)
            let nsAmount = NSDecimalNumber(decimal: absAmount).doubleValue
            return nsAmount.truncatingRemainder(dividingBy: 10) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 25) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 50) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 100) == 0
        }

        private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
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

        private static func jaccardSimilarity(_ s1: String, _ s2: String) -> Double {
            let set1 = Set(s1.split(separator: " ").map { String($0) })
            let set2 = Set(s2.split(separator: " ").map { String($0) })

            guard !set1.isEmpty || !set2.isEmpty else { return 1.0 }

            let intersection = set1.intersection(set2).count
            let union = set1.union(set2).count

            return union > 0 ? Double(intersection) / Double(union) : 0.0
        }

        private static func areAccountTypesCompatible(_ type1: AccountType, _ type2: AccountType) -> Bool {
            // Common transfer pairs
            let commonPairs: Set<Set<AccountType>> = [
                [.chequing, .savings],
                [.chequing, .creditCard],
                [.savings, .investment],
                [.chequing, .investment]
            ]

            let pair = Set([type1, type2])
            return commonPairs.contains(pair) || type1 == type2
        }
    }
}
