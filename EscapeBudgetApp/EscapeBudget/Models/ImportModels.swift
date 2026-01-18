import Foundation
import SwiftData
import SwiftUI

// MARK: - Constants

enum ImportConstants {
    static let previewRowLimit = 50
    static let batchSaveInterval = 250
    static let progressUpdateInterval = 25
    static let parseProgressInterval = 50
}

// MARK: - ImportedTransaction

/// Temporary model for holding parsed transactions before import
struct ImportedTransaction: Identifiable, Sendable {
    let id = UUID()
    var date: Date
    var payee: String
    var rawPayee: String? = nil
    var amount: Decimal
    var memo: String?
    var rawCategory: String? = nil
    var rawAccount: String? = nil
    var rawTags: [String] = []
    var status: TransactionStatus = .uncleared
    var isSelected: Bool = true
    var isDuplicate: Bool = false
    var duplicateReason: String? = nil
    var kind: TransactionKind = .standard
    var transferID: UUID? = nil
    var transferInboxDismissed: Bool = false
    var externalTransferLabel: String? = nil
    var purchaseItemsJSON: String? = nil
    
    /// Create a real Transaction from this import preview
    func toTransaction(account: Account, category: Category? = nil, tags: [TransactionTag]? = nil) -> Transaction {
        let tx = Transaction(
            date: date,
            payee: payee,
            amount: amount,
            memo: memo,
            status: status,
            kind: kind,
            transferID: transferID,
            account: account,
            category: category,
            tags: tags
        )
        tx.transferInboxDismissed = transferInboxDismissed
        tx.externalTransferLabel = externalTransferLabel
        return tx
    }
}

/// Supported date formats for parsing
enum DateFormatOption: String, CaseIterable, Identifiable, Sendable {
    case mmddyyyy = "MM/DD/YYYY"
    case ddmmyyyy = "DD/MM/YYYY"
    case yyyymmdd = "YYYY-MM-DD"
    case mdyy = "M/D/YY"
    case mdy = "M/D/YYYY"
    case dmyyyy = "D/M/YYYY"
    
    var id: String { rawValue }
    
    nonisolated var formatString: String {
        switch self {
        case .mmddyyyy: return "MM/dd/yyyy"
        case .ddmmyyyy: return "dd/MM/yyyy"
        case .yyyymmdd: return "yyyy-MM-dd"
        case .mdyy: return "M/d/yy"
        case .mdy: return "M/d/yyyy"
        case .dmyyyy: return "d/M/yyyy"
        }
    }
    
    nonisolated func parse(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = formatString
        return formatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }
}

/// Column mapping options for import
enum ColumnType: String, CaseIterable, Identifiable, Sendable {
    case date = "Date"
    case payee = "Payee"
    case amount = "Amount"
    case inflow = "Inflow"
    case outflow = "Outflow"
    case memo = "Memo"
    case category = "Category"
    case account = "Account"
    case tags = "Tags"
    case status = "Status"
    case kind = "Kind"
    case transferID = "Transfer ID"
    case externalTransferLabel = "External Transfer Label"
    case transferInboxDismissed = "Transfer Inbox Dismissed"
    case purchaseItems = "Purchase Items"
    case skip = "skip"

    var id: String { rawValue }

    func color(for mode: AppColorMode) -> Color {
        switch self {
        case .date: return AppColors.tint(for: mode)
        case .payee: return AppColors.warning(for: mode)
        case .amount: return AppColors.success(for: mode)
        case .inflow: return AppColors.success(for: mode)
        case .outflow: return AppColors.danger(for: mode)
        case .memo: return .purple
        case .category: return .teal
        case .account: return .indigo
        case .tags: return .pink
        case .status: return .mint
        case .kind: return .orange
        case .transferID: return .orange
        case .externalTransferLabel: return .orange
        case .transferInboxDismissed: return .orange
        case .purchaseItems: return .purple
        case .skip: return .gray
        }
    }

    var color: Color {
        color(for: AppColors.currentModeFromDefaults())
    }
}

// MARK: - AmountSignConvention

enum AmountSignConvention: String, CaseIterable, Identifiable {
    case positiveIsIncome = "Positive = Income"
    case positiveIsExpense = "Positive = Expense"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .positiveIsIncome:
            return "Positive numbers are treated as income; negative numbers are expenses."
        case .positiveIsExpense:
            return "Positive numbers are treated as expenses; negative numbers are income."
        }
    }
}

enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case custom = "Custom"
    case ynab = "YNAB"
    case mint = "Mint"
    case monarch = "Monarch"
    case chase = "Chase Bank"
    case bankOfAmerica = "Bank of America"
    case wellsFargo = "Wells Fargo"
    case citi = "Citibank"
    case capitalOne = "Capital One"
    case discover = "Discover"
    case amex = "American Express"
    case paypal = "PayPal"
    case venmo = "Venmo"
    case cashApp = "Cash App"
    // Canadian Banks
    case rbc = "RBC Royal Bank"
    case td = "TD Canada Trust"
    case scotiabank = "Scotiabank"
    case bmo = "BMO Bank of Montreal"
    case cibc = "CIBC"
    case nationalBank = "National Bank of Canada"
    case tangerine = "Tangerine"
    case simplii = "Simplii Financial"
    case wealthsimple = "Wealthsimple"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .custom: return "Generic CSV with flexible mapping"
        case .ynab: return "You Need A Budget export format"
        case .mint: return "Mint.com export format"
        case .monarch: return "Monarch Money export format"
        case .chase: return "Chase Bank transaction export"
        case .bankOfAmerica: return "Bank of America transaction export"
        case .wellsFargo: return "Wells Fargo transaction export"
        case .citi: return "Citibank transaction export"
        case .capitalOne: return "Capital One transaction export"
        case .discover: return "Discover Card transaction export"
        case .amex: return "American Express transaction export"
        case .paypal: return "PayPal transaction history"
        case .venmo: return "Venmo transaction history"
        case .cashApp: return "Cash App transaction history"
        case .rbc: return "RBC Royal Bank transaction export"
        case .td: return "TD Canada Trust transaction export"
        case .scotiabank: return "Scotiabank transaction export"
        case .bmo: return "BMO Bank of Montreal transaction export"
        case .cibc: return "CIBC transaction export"
        case .nationalBank: return "National Bank of Canada transaction export"
        case .tangerine: return "Tangerine transaction export"
        case .simplii: return "Simplii Financial transaction export"
        case .wealthsimple: return "Wealthsimple transaction export"
        }
    }

    /// Category for organizing import sources
    var category: ImportSourceCategory {
        switch self {
        case .custom:
            return .custom
        case .ynab, .mint, .monarch:
            return .personalFinance
        case .chase, .bankOfAmerica, .wellsFargo, .citi, .capitalOne, .discover, .amex:
            return .usBank
        case .rbc, .td, .scotiabank, .bmo, .cibc, .nationalBank, .tangerine, .simplii, .wealthsimple:
            return .canadianBank
        case .paypal, .venmo, .cashApp:
            return .paymentApp
        }
    }

    /// Returns a sorted list of import sources based on currency preference and last used
    static func sortedSources(currencyCode: String, lastUsed: ImportSource?) -> [ImportSource] {
        var sources: [ImportSource] = []

        // 1. Last used (if available and not custom)
        if let lastUsed, lastUsed != .custom {
            sources.append(lastUsed)
        }

        // 2. Always start with Custom
        sources.append(.custom)

        // 3. Personal Finance Apps
        sources.append(contentsOf: [.ynab, .mint, .monarch])

        // 4. Banks based on currency
        let isCanadian = currencyCode == "CAD"
        if isCanadian {
            // Canadian banks first
            sources.append(contentsOf: [.rbc, .td, .scotiabank, .bmo, .cibc, .nationalBank, .tangerine, .simplii, .wealthsimple])
            // Then US banks
            sources.append(contentsOf: [.chase, .bankOfAmerica, .wellsFargo, .citi, .capitalOne, .discover, .amex])
        } else {
            // US banks first
            sources.append(contentsOf: [.chase, .bankOfAmerica, .wellsFargo, .citi, .capitalOne, .discover, .amex])
            // Then Canadian banks
            sources.append(contentsOf: [.rbc, .td, .scotiabank, .bmo, .cibc, .nationalBank, .tangerine, .simplii, .wealthsimple])
        }

        // 5. Payment Apps
        sources.append(contentsOf: [.paypal, .venmo, .cashApp])

        // Remove duplicates while preserving order
        var seen: Set<ImportSource> = []
        return sources.filter { seen.insert($0).inserted }
    }
}

/// Categories for grouping import sources
enum ImportSourceCategory {
    case custom
    case personalFinance
    case usBank
    case canadianBank
    case paymentApp
}

// MARK: - Import Progress State

/// State for displaying import progress UI
struct ImportProgressState: Equatable {
    enum Phase: String {
        case parsing = "Parsing CSV"
        case preparing = "Preparing"
        case saving = "Saving"
        case processing = "Processing"
    }

    var title: String
    var phase: Phase
    var message: String
    var current: Int
    var total: Int?
    var canCancel: Bool
}

// MARK: - Import Parsing Utilities

enum ImportParser {
    /// All supported date format strings for auto-detection
    nonisolated static let supportedDateFormats: [String] = [
        "MM/dd/yyyy", "M/d/yyyy", "dd/MM/yyyy", "d/M/yyyy",
        "yyyy-MM-dd", "yyyy/MM/dd", "MM-dd-yyyy", "dd-MM-yyyy",
        "yyyyMMdd", "MMM d, yyyy", "d MMM yyyy",
        "yyyy-MM-dd HH:mm:ss", "MM/dd/yyyy HH:mm:ss"
    ]

    /// Parse a monetary amount string into a Decimal
    /// Handles currency symbols, commas, and parentheses for negative values
    nonisolated static func parseAmount(_ str: String) -> Decimal? {
        let clean = str
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Handle (100) as negative
        if clean.hasPrefix("(") && clean.hasSuffix(")") {
            let num = clean
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            return Decimal(string: num).map { -$0 }
        }
        return Decimal(string: clean)
    }

    /// Parse a date string using the specified format option or auto-detect
    nonisolated static func parseDate(from value: String, option: DateFormatOption?) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // If a specific format is specified, use it
        if let manual = option {
            return manual.parse(trimmed)
        }

        // Try ISO8601 first
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }

        // Try common formats
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for fmt in supportedDateFormats {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: trimmed) { return d }
        }
        return nil
    }

    /// Parse tags from a comma or semicolon separated string
    nonisolated static func parseTags(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let separators = CharacterSet(charactersIn: ",;")
        return trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
