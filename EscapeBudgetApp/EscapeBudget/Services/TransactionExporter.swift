import Foundation
import SwiftData

// Import the ExportFormat enum from ExportDataView
enum ExportFormat_Internal: String {
    case standard
    case ynab
    case mint
}

final class TransactionExporter {

    func exportTransactions(_ transactions: [Transaction], to url: URL, format: ExportFormat) throws {
        let data = exportCSVData(transactions, format: format)
        try data.write(to: url, options: [.atomic])
    }

    func exportTransactions(_ transactions: [Transaction], to url: URL) throws {
        // Legacy method for backwards compatibility
        var csvString = ""

        // Add header row
        let headers = ["Date", "Payee", "Memo", "Amount", "Account", "Category", "Status", "Kind", "Transfer ID", "Purchase Items"]
        csvString += headers.joined(separator: ",") + "\n"

        // Add data rows
        for transaction in transactions {
            let dateString = formatDate(transaction.date)
            let payee = escapeCSV(transaction.payee)
            let memo = transaction.memo.map { escapeCSV($0) } ?? ""
            let amount = transaction.amount.description
            let account = escapeCSV(transaction.account?.name ?? "")
            let category = escapeCSV(transaction.category?.name ?? "")
            let status = transaction.status.rawValue
            let kind = escapeCSV(transaction.kindRawValue)
            let transferID = transaction.transferID?.uuidString ?? ""
            let purchaseItems = PurchasedItemsCSVCodec.encode(transaction.purchasedItems).map(escapeCSV) ?? ""

            let row = [
                dateString,
                payee,
                memo,
                amount,
                account,
                category,
                status,
                kind,
                transferID,
                purchaseItems
            ]

            csvString += row.joined(separator: ",") + "\n"
        }

        // Write to file
        try csvString.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportCSVData(_ transactions: [Transaction], format: ExportFormat) -> Data {
        let csvString = exportCSVString(transactions, format: format)
        return Data(csvString.utf8)
    }

    private func exportCSVString(_ transactions: [Transaction], format: ExportFormat) -> String {
        switch format {
        case .standard:
            return exportStandard(transactions)
        case .ynab:
            return exportYNAB(transactions)
        case .mint:
            return exportMint(transactions)
        }
    }

    private func exportStandard(_ transactions: [Transaction]) -> String {
        var csvString = ""

        let headers = [
            "Date",
            "Payee",
            "Memo",
            "Amount",
            "Account",
            "Category",
            "Tags",
            "Status",
            "Kind",
            "Transfer ID",
            "External Transfer Label",
            "Transfer Inbox Dismissed",
            "Purchase Items"
        ]
        csvString += headers.joined(separator: ",") + "\n"

        for transaction in transactions {
            let dateString = formatDate(transaction.date)
            let payee = escapeCSV(transaction.payee)
            let memo = transaction.memo.map { escapeCSV($0) } ?? ""
            let amount = transaction.amount.description
            let account = escapeCSV(transaction.account?.name ?? "")
            let category = escapeCSV(transaction.category?.name ?? "")
            let tags = transaction.tags?.map { $0.name }.joined(separator: ";") ?? ""
            let status = transaction.status.rawValue
            let kind = escapeCSV(transaction.kindRawValue)
            let transferID = transaction.transferID?.uuidString ?? ""
            let externalTransferLabel = transaction.externalTransferLabel.map { escapeCSV($0) } ?? ""
            let transferInboxDismissed = transaction.transferInboxDismissed ? "true" : "false"
            let purchaseItems = PurchasedItemsCSVCodec.encode(transaction.purchasedItems).map(escapeCSV) ?? ""

            let row = [
                dateString,
                payee,
                memo,
                amount,
                account,
                category,
                escapeCSV(tags),
                status,
                kind,
                transferID,
                externalTransferLabel,
                transferInboxDismissed,
                purchaseItems
            ]
            csvString += row.joined(separator: ",") + "\n"
        }

        return csvString
    }

    private func exportYNAB(_ transactions: [Transaction]) -> String {
        var csvString = ""

        let headers = ["Date", "Payee", "Category", "Memo", "Outflow", "Inflow"]
        csvString += headers.joined(separator: ",") + "\n"

        for transaction in transactions {
            let dateString = formatDate(transaction.date)
            let payee = escapeCSV(transaction.payee)
            let category = escapeCSV(transaction.category?.name ?? "")
            let memo = transaction.memo.map { escapeCSV($0) } ?? ""

            // YNAB uses separate inflow/outflow columns
            let outflow = transaction.amount < 0 ? abs(transaction.amount).description : ""
            let inflow = transaction.amount >= 0 ? transaction.amount.description : ""

            let row = [dateString, payee, category, memo, outflow, inflow]
            csvString += row.joined(separator: ",") + "\n"
        }

        return csvString
    }

    private func exportMint(_ transactions: [Transaction]) -> String {
        var csvString = ""

        let headers = ["Date", "Description", "Original Description", "Amount", "Transaction Type", "Category", "Account Name", "Labels", "Notes"]
        csvString += headers.joined(separator: ",") + "\n"

        for transaction in transactions {
            let dateString = formatDate(transaction.date)
            let description = escapeCSV(transaction.payee)
            let originalDescription = escapeCSV(transaction.payee)
            let amount = transaction.amount.description
            let transactionType = transaction.amount < 0 ? "debit" : "credit"
            let category = escapeCSV(transaction.category?.name ?? "")
            let accountName = escapeCSV(transaction.account?.name ?? "")
            let labels = transaction.tags?.map { $0.name }.joined(separator: ",") ?? ""
            let notes = transaction.memo.map { escapeCSV($0) } ?? ""

            let row = [dateString, description, originalDescription, amount, transactionType, category, accountName, escapeCSV(labels), notes]
            csvString += row.joined(separator: ",") + "\n"
        }

        return csvString
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy" // YNAB compatible format
        return formatter.string(from: date)
    }

    private func escapeCSV(_ string: String) -> String {
        var sanitized = string

        // Prevent CSV injection by prefixing formula characters with single quote
        // These characters can trigger formula execution in spreadsheet applications
        let formulaStarters: [Character] = ["=", "+", "-", "@", "\t", "\r"]
        if let firstChar = sanitized.first, formulaStarters.contains(firstChar) {
            sanitized = "'" + sanitized
        }

        // If the string contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if sanitized.contains(",") || sanitized.contains("\"") || sanitized.contains("\n") {
            let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return sanitized
    }
}
