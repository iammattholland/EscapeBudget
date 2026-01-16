import Foundation

enum TransactionDeduper {
    struct Result: Equatable {
        var isDuplicate: Bool
        var reason: String?
    }

    struct Config: Equatable {
        var useNormalizedPayee: Bool = true
        var similarityThreshold: Double = 0.85
    }

    static func evaluate(
        imported: ImportedTransaction,
        existing: Transaction,
        config: Config
    ) -> Result {
        let calendar = Calendar.current

        guard calendar.isDate(existing.date, inSameDayAs: imported.date) else {
            return Result(isDuplicate: false, reason: nil)
        }

        guard existing.amount == imported.amount else {
            return Result(isDuplicate: false, reason: nil)
        }

        let importedPayee = imported.rawPayee ?? imported.payee
        let left = config.useNormalizedPayee
            ? PayeeNormalizer.normalizeForComparison(importedPayee)
            : importedPayee.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let right = config.useNormalizedPayee
            ? PayeeNormalizer.normalizeForComparison(existing.payee)
            : existing.payee.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if left == right {
            return Result(isDuplicate: true, reason: "Exact payee match")
        }

        if left.hasPrefix(right) || right.hasPrefix(left) {
            return Result(isDuplicate: true, reason: "Payee prefix match")
        }

        let similarity = stringSimilarity(left, right)
        if similarity >= config.similarityThreshold {
            return Result(isDuplicate: true, reason: "Payee similarity \(Int(similarity * 100))%")
        }

        if let importedMemo = imported.memo?.lowercased(), let existingMemo = existing.memo?.lowercased() {
            let a = importedMemo.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = existingMemo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty, a == b {
                return Result(isDuplicate: true, reason: "Memo match")
            }
        }

        return Result(isDuplicate: false, reason: nil)
    }

    /// Calculates similarity ratio between two strings (0.0 to 1.0)
    /// Uses Levenshtein distance.
    private static func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        guard !s1.isEmpty && !s2.isEmpty else { return 0.0 }
        if s1 == s2 { return 1.0 }

        let longer = s1.count >= s2.count ? s1 : s2
        let shorter = s1.count < s2.count ? s1 : s2

        let longerLength = longer.count
        guard longerLength > 0 else { return 1.0 }

        let distance = levenshteinDistance(longer, shorter)
        return (Double(longerLength) - Double(distance)) / Double(longerLength)
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }
}

