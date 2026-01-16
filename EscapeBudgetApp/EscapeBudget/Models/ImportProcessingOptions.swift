import Foundation

/// Per-import processing options chosen by the user during CSV import.
/// These are prompts during import (not buried in Settings), and are shown again in the import review.
struct ImportProcessingOptions: Equatable {
    var normalizePayee: Bool
    var applyAutoRules: Bool
    var detectDuplicates: Bool
    var suggestTransfers: Bool
    var saveProcessingHistory: Bool

    var summary: String {
        let parts: [String] = [
            normalizePayee ? "Payee cleanup" : nil,
            applyAutoRules ? "Auto rules" : nil,
            detectDuplicates ? "Duplicates" : nil,
            suggestTransfers ? "Transfer suggestions" : nil,
            saveProcessingHistory ? "History" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "No automation" : parts.joined(separator: " • ")
    }
}

