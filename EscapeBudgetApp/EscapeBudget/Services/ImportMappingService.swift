import Foundation
import SwiftData

/// Service for auto-mapping imported data to existing accounts, categories, and tags
@MainActor
enum ImportMappingService {

    // MARK: - Account Mapping

    /// Auto-map imported account names to existing accounts by matching names
    static func autoMapAccounts(
        importedAccounts: [String],
        existingAccounts: [Account]
    ) -> [String: Account] {
        var mapping: [String: Account] = [:]

        for raw in importedAccounts {
            if let match = existingAccounts.first(where: {
                $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                mapping[raw] = match
            }
        }

        return mapping
    }

    /// Suggest account type based on account name heuristics
    static func suggestedAccountType(for rawAccountName: String) -> AccountType {
        let lower = rawAccountName.lowercased()
        let tokens = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let collapsed = lower
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        if tokens.contains("mortgage") { return .mortgage }
        if tokens.contains("loan") || tokens.contains("loans") { return .loans }
        if tokens.contains("savings") { return .savings }
        if tokens.contains("investment") || tokens.contains("brokerage") { return .investment }
        if collapsed.contains("401k") || collapsed.contains("rrsp") || collapsed.contains("tfsa") { return .investment }
        if tokens.contains("credit") && (tokens.contains("card") || collapsed.contains("cc")) { return .creditCard }
        if tokens.contains("checking") || tokens.contains("chequing") { return .chequing }
        if tokens.contains("line") && tokens.contains("credit") { return .lineOfCredit }
        if tokens.contains("cash") { return .other }

        // Default
        return .chequing
    }

    // MARK: - Category Mapping

    /// Auto-map imported category names to existing categories by matching names
    static func autoMapCategories(
        importedCategories: [String],
        existingCategories: [Category]
    ) -> [String: Category] {
        var mapping: [String: Category] = [:]

        for raw in importedCategories {
            if let match = existingCategories.first(where: {
                $0.name.lowercased() == raw.lowercased()
            }) {
                mapping[raw] = match
            }
        }

        return mapping
    }

    // MARK: - Tag Mapping

    /// Auto-map imported tag names to existing tags by matching names
    static func autoMapTags(
        importedTags: [String],
        existingTags: [TransactionTag]
    ) -> [String: TransactionTag] {
        var mapping: [String: TransactionTag] = [:]

        for raw in importedTags {
            if let match = existingTags.first(where: {
                $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                mapping[raw] = match
            }
        }

        return mapping
    }

    // MARK: - Column Mapping Detection

    /// Auto-detect column mappings based on header names
    static func detectColumnMapping(headers: [String]) -> [Int: String] {
        var mapping: [Int: String] = [:]

        for (index, header) in headers.enumerated() {
            let lower = header.lowercased().trimmingCharacters(in: .whitespaces)

            // Date
            if lower.contains("date") {
                mapping[index] = "Date"
            }
            // Payee
            else if lower.contains("payee") || lower.contains("description") || lower.contains("merchant") || lower.contains("name") {
                mapping[index] = "Payee"
            }
            // Amount
            else if lower == "amount" || lower == "amt" {
                mapping[index] = "Amount"
            }
            // Inflow/Outflow
            else if lower.contains("inflow") || lower.contains("deposit") || lower.contains("credit") {
                mapping[index] = "Inflow"
            }
            else if lower.contains("outflow") || lower.contains("withdrawal") || lower.contains("debit") || lower.contains("payment") {
                mapping[index] = "Outflow"
            }
            // Memo
            else if lower.contains("memo") || lower.contains("note") {
                mapping[index] = "Memo"
            }
            // Category
            else if lower.contains("category") {
                mapping[index] = "Category"
            }
            // Account
            else if lower.contains("account") {
                mapping[index] = "Account"
            }
            // Tags
            else if lower.contains("tag") || lower.contains("label") {
                mapping[index] = "Tags"
            }
            // Status
            else if lower.contains("status") || lower.contains("cleared") {
                mapping[index] = "Status"
            }
        }

        return mapping
    }

    /// Detect header row index by looking for common transaction headers
    static func detectHeaderRow(in rows: [[String]]) -> Int {
        guard !rows.isEmpty else { return 0 }

        let maxRowsToCheck = min(10, rows.count)

        for (index, row) in rows.prefix(maxRowsToCheck).enumerated() {
            let lower = row.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

            // Look for common headers
            let hasDate = lower.contains { $0.contains("date") }
            let hasAmount = lower.contains { $0.contains("amount") || $0 == "amt" }
            let hasPayee = lower.contains { $0.contains("payee") || $0.contains("description") || $0.contains("merchant") }

            if hasDate && (hasAmount || hasPayee) {
                return index
            }
        }

        return 0
    }
}
