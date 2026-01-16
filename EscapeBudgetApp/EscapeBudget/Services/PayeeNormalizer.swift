import Foundation

enum PayeeNormalizer {
    /// Normalizes a payee for display (keeps it readable).
    static func normalizeDisplay(_ payee: String) -> String {
        var value = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        // Collapse whitespace
        value = value
            .replacingOccurrences(of: "[\\t\\n\\r]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop common noisy prefixes (conservative)
        let prefixes = [
            "POS PURCHASE ",
            "POS ",
            "DEBIT ",
            "CREDIT ",
            "PURCHASE ",
            "ACH ",
            "EFT ",
            "INTERAC ",
            "VISA ",
            "MASTERCARD "
        ]
        let upper = value.uppercased()
        for prefix in prefixes where upper.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // If the remaining string is mostly uppercase, title-case it.
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if !letters.isEmpty {
            let upperLetters = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            let ratio = Double(upperLetters) / Double(letters.count)
            if ratio > 0.75 {
                value = value.lowercased().capitalized
            }
        }

        return value
    }

    /// Normalizes a payee for comparisons (duplicates/rules), more aggressive.
    static func normalizeForComparison(_ payee: String) -> String {
        normalizeDisplay(payee)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

