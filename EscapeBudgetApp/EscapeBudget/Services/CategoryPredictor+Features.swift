import Foundation
import SwiftData

extension CategoryPredictor {
    /// Features extracted from a transaction for category prediction
    struct CategoryFeatures {
        let transaction: Transaction

        // Payee features
        let payee: String
        let payeeWords: Set<String>
        let payeeLength: Int

        // Amount features
        let amount: Decimal
        let isRoundNumber: Bool
        let amountRange: AmountRange

        // Temporal features
        let dayOfWeek: Int
        let isWeekend: Bool
        let hourOfDay: Int

        // Text features
        let memo: String
        let memoWords: Set<String>
        let hasTransferKeywords: Bool

        // Account features
        let accountType: AccountType

        enum AmountRange {
            case micro      // < $10
            case small      // $10-$50
            case medium     // $50-$200
            case large      // $200-$1000
            case veryLarge  // > $1000
        }

        init(transaction: Transaction) {
            self.transaction = transaction

            // Payee features
            let normalizedPayee = PayeeNormalizer.normalizeForComparison(transaction.payee)
            self.payee = normalizedPayee
            self.payeeWords = Set(normalizedPayee.split(separator: " ").map { String($0) })
            self.payeeLength = normalizedPayee.count

            // Amount features
            let absAmount = abs(transaction.amount)
            self.amount = absAmount
            self.isRoundNumber = Self.isRoundAmount(absAmount)

            if absAmount < 10 {
                self.amountRange = .micro
            } else if absAmount < 50 {
                self.amountRange = .small
            } else if absAmount < 200 {
                self.amountRange = .medium
            } else if absAmount < 1000 {
                self.amountRange = .large
            } else {
                self.amountRange = .veryLarge
            }

            // Temporal features
            let calendar = Calendar.current
            self.dayOfWeek = calendar.component(.weekday, from: transaction.date)
            self.isWeekend = dayOfWeek == 1 || dayOfWeek == 7
            self.hourOfDay = calendar.component(.hour, from: transaction.date)

            // Text features
            let memoText = transaction.memo ?? ""
            self.memo = memoText.lowercased()
            self.memoWords = Set(memoText.lowercased().split(separator: " ").map { String($0) })

            let transferKeywords = ["transfer", "xfer", "tfr", "atm", "withdrawal", "deposit", "move", "payment to"]
            let memoLower = memoText.lowercased()
            let payeeLower = payee
            let hasKeywords = transferKeywords.contains { keyword in
                payeeLower.contains(keyword) || memoLower.contains(keyword)
            }
            self.hasTransferKeywords = hasKeywords

            // Account features
            self.accountType = transaction.account?.type ?? .chequing
        }

        // MARK: - Helper Methods

        private static func isRoundAmount(_ amount: Decimal) -> Bool {
            let nsAmount = NSDecimalNumber(decimal: abs(amount)).doubleValue
            return nsAmount.truncatingRemainder(dividingBy: 10) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 25) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 50) == 0 ||
                   nsAmount.truncatingRemainder(dividingBy: 100) == 0
        }

        /// Calculate Jaccard similarity between two sets of words
        static func jaccardSimilarity(_ set1: Set<String>, _ set2: Set<String>) -> Double {
            guard !set1.isEmpty || !set2.isEmpty else { return 1.0 }

            let intersection = set1.intersection(set2).count
            let union = set1.union(set2).count

            return union > 0 ? Double(intersection) / Double(union) : 0.0
        }
    }
}
