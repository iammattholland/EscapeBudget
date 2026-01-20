import Foundation
import SwiftData

/// ML-based payee normalization service
@MainActor
final class PayeeNormalizerML {
    private let modelContext: ModelContext

    struct Suggestion {
        let canonicalName: String
        let confidence: Double
        let pattern: PayeePattern
        let reason: String
    }

    struct Config {
        var minConfidenceThreshold: Double = 0.6
        var useMLNormalization: Bool = true
        var levenshteinThreshold: Int = 3  // Max edit distance for fuzzy matching

        nonisolated init(minConfidenceThreshold: Double = 0.6, useMLNormalization: Bool = true, levenshteinThreshold: Int = 3) {
            self.minConfidenceThreshold = minConfidenceThreshold
            self.useMLNormalization = useMLNormalization
            self.levenshteinThreshold = levenshteinThreshold
        }
    }

    private let config: Config

    init(modelContext: ModelContext, config: Config = Config()) {
        self.modelContext = modelContext
        self.config = config
    }

    private func comparisonKey(_ string: String) -> String {
        let normalized = PayeeNormalizer.normalizeForComparison(string)
        let withoutNumbers = normalized
            .replacingOccurrences(of: "\\b\\d+\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutNumbers.isEmpty ? normalized : withoutNumbers
    }

    private func adjustedConfidence(base: Double, patternConfidence: Double) -> Double {
        // Blend string similarity with learned confidence so newer patterns can still suggest.
        (base * 0.75) + (patternConfidence * 0.25)
    }

    /// Normalize a payee name using learned patterns
    func normalize(_ payee: String) -> Suggestion? {
        guard config.useMLNormalization else { return nil }
        guard !payee.isEmpty else { return nil }

        // First, check for exact matches
        if let exactMatch = findExactMatch(payee) {
            return Suggestion(
                canonicalName: exactMatch.canonicalName,
                confidence: 1.0,
                pattern: exactMatch,
                reason: "exact match"
            )
        }

        // Then try fuzzy matching
        if let fuzzyMatch = findFuzzyMatch(payee) {
            return fuzzyMatch
        }

        return nil
    }

    /// Get multiple normalization suggestions
    func getSuggestions(for payee: String, limit: Int = 3) -> [Suggestion] {
        guard config.useMLNormalization else { return [] }
        guard !payee.isEmpty else { return [] }

        var suggestions: [Suggestion] = []

        // Check exact matches first
        if let exactMatch = findExactMatch(payee) {
            suggestions.append(Suggestion(
                canonicalName: exactMatch.canonicalName,
                confidence: 1.0,
                pattern: exactMatch,
                reason: "exact match"
            ))
        }

        // Add fuzzy matches
        let fuzzyMatches = findFuzzyMatches(payee, limit: limit)
        suggestions.append(contentsOf: fuzzyMatches)

        return Array(suggestions.prefix(limit))
    }

    /// Learn from user's payee rename
    func learnFromRename(original: String, canonical: String) {
        guard !original.isEmpty && !canonical.isEmpty else { return }
        guard original.lowercased() != canonical.lowercased() else { return }

        // Find existing pattern for this canonical name
        if let pattern = fetchPattern(canonicalName: canonical) {
            pattern.addVariant(original)
            pattern.useCount += 1
            pattern.lastUsedAt = Date()
            pattern.confidence = min(1.0, pattern.confidence + 0.1)
        } else {
            // Create new pattern
            let pattern = PayeePattern(canonicalName: canonical, variant: original)
            modelContext.insert(pattern)
        }

        _ = modelContext.safeSave(
            context: "PayeeNormalizerML.learnFromRename",
            showErrorToUser: false
        )
    }

    /// Learn from confirmed normalization
    func learnFromConfirmation(payee: String, pattern: PayeePattern) {
        pattern.useCount += 1
        pattern.lastUsedAt = Date()
        pattern.confidence = min(1.0, pattern.confidence + 0.05)

        _ = modelContext.safeSave(
            context: "PayeeNormalizerML.learnFromConfirmation",
            showErrorToUser: false
        )
    }

    /// Learn from rejected suggestion
    func learnFromRejection(payee: String, pattern: PayeePattern) {
        pattern.confidence = max(0.0, pattern.confidence - 0.1)

        _ = modelContext.safeSave(
            context: "PayeeNormalizerML.learnFromRejection",
            showErrorToUser: false
        )
    }

    /// Bulk learn from existing transaction history
    func learnFromHistory() async {
        // Find transactions where payee was renamed via auto-rules
        let descriptor = FetchDescriptor<AutoRuleApplication>(
            predicate: #Predicate { $0.fieldChanged == "payee" }
        )

        guard let applications = try? modelContext.fetch(descriptor) else { return }

        var processedCount = 0
        for app in applications {
            guard let oldValue = app.oldValue,
                  let newValue = app.newValue else { continue }

            learnFromRename(original: oldValue, canonical: newValue)

            processedCount += 1
            if processedCount % 50 == 0 {
                await Task.yield()
            }
        }
    }

    /// Clean up unreliable patterns
    func cleanupUnreliablePatterns(olderThan days: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<PayeePattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []

        for pattern in allPatterns {
            if pattern.lastUsedAt < cutoffDate && !pattern.isReliable {
                modelContext.delete(pattern)
            } else if pattern.confidence < 0.2 {
                modelContext.delete(pattern)
            }
        }

        _ = modelContext.safeSave(
            context: "PayeeNormalizerML.cleanup",
            showErrorToUser: false
        )
    }

    // MARK: - Private Methods

    private func findExactMatch(_ payee: String) -> PayeePattern? {
        let descriptor = FetchDescriptor<PayeePattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []

        return allPatterns.first { pattern in
            pattern.matches(payee)
        }
    }

    private func findFuzzyMatch(_ payee: String) -> Suggestion? {
        let matches = findFuzzyMatches(payee, limit: 1)
        return matches.first
    }

    private func findFuzzyMatches(_ payee: String, limit: Int) -> [Suggestion] {
        let normalized = comparisonKey(payee)

        let descriptor = FetchDescriptor<PayeePattern>(
            sortBy: [SortDescriptor(\.confidence, order: .reverse)]
        )
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []

        var suggestions: [Suggestion] = []

        for pattern in allPatterns {
            // Check Levenshtein distance against canonical name and variants
            let canonicalKey = comparisonKey(pattern.canonicalName)
            let canonicalDistance = levenshteinDistance(normalized, canonicalKey)

            if canonicalDistance <= config.levenshteinThreshold {
                let base = 1.0 - (Double(canonicalDistance) / Double(max(max(normalized.count, canonicalKey.count), 1)))
                let adjusted = adjustedConfidence(base: base, patternConfidence: pattern.confidence)

                if adjusted >= config.minConfidenceThreshold {
                    suggestions.append(Suggestion(
                        canonicalName: pattern.canonicalName,
                        confidence: adjusted,
                        pattern: pattern,
                        reason: "similar name (distance: \(canonicalDistance))"
                    ))
                }
            }

            // Also check variants
            for variant in pattern.variants {
                let variantKey = comparisonKey(variant)
                let variantDistance = levenshteinDistance(normalized, variantKey)
                if variantDistance <= config.levenshteinThreshold {
                    let base = 1.0 - (Double(variantDistance) / Double(max(max(normalized.count, variantKey.count), 1)))
                    let adjusted = adjustedConfidence(base: base, patternConfidence: pattern.confidence)

                    if adjusted >= config.minConfidenceThreshold {
                        // Don't add duplicate suggestions
                        if !suggestions.contains(where: { $0.pattern.canonicalName == pattern.canonicalName }) {
                            suggestions.append(Suggestion(
                                canonicalName: pattern.canonicalName,
                                confidence: adjusted,
                                pattern: pattern,
                                reason: "similar to known variant (distance: \(variantDistance))"
                            ))
                        }
                    }
                }
            }
        }

        return suggestions
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }

    private func fetchPattern(canonicalName: String) -> PayeePattern? {
        let normalized = canonicalName.lowercased()
        let descriptor = FetchDescriptor<PayeePattern>()
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []
        return allPatterns.first { $0.canonicalName.lowercased() == normalized }
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
