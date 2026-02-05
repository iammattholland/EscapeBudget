import Foundation
import SwiftData

@Model
final class Transaction: DemoDataTrackable {
    var date: Date
    var payee: String
    var amount: Decimal
    var memo: String?
    var statusRawValue: String
    var kindRawValue: String
    var transferID: UUID?
    var transferInboxDismissed: Bool = false
    var externalTransferLabel: String?
    var isDemoData: Bool = false

    @Relationship
    var tags: [TransactionTag]?
    
    @Relationship(inverse: \Account.transactions)
    var account: Account?
    
    @Relationship(inverse: \Category.transactions)
    var category: Category?
    
    @Relationship(inverse: \Transaction.subtransactions)
    var parentTransaction: Transaction?
    
    @Relationship(deleteRule: .cascade)
    var subtransactions: [Transaction]?
    
    @Relationship(deleteRule: .cascade)
    var historyEntries: [TransactionHistoryEntry]?

    @Relationship(deleteRule: .cascade)
    var purchasedItems: [PurchasedItem]?

    @Relationship(deleteRule: .cascade, inverse: \ReceiptImage.transaction)
    var receipt: ReceiptImage?

    /// For unmatched transfers: the account this transfer is intended for, even if we don't have the paired transaction yet.
    /// This is for record-keeping only and doesn't affect account balances.
    @Relationship(inverse: \Account.intendedTransferTransactions)
    var intendedTransferAccount: Account?

    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRawValue) ?? .uncleared }
        set { statusRawValue = newValue.rawValue }
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .standard }
        set { kindRawValue = newValue.rawValue }
    }

    var isTransfer: Bool {
        kind == .transfer
    }

    var isAdjustment: Bool {
        kind == .adjustment
    }

    var isIgnored: Bool {
        kind == .ignored
    }

    var isPairedTransfer: Bool {
        kind == .transfer && transferID != nil
    }

    var isUncategorized: Bool {
        kind == .standard && category == nil
    }

    var isExternalTransfer: Bool {
        kind == .transfer && externalTransferLabel != nil
    }

    init(
        date: Date,
        payee: String,
        amount: Decimal,
        memo: String? = nil,
        status: TransactionStatus = .uncleared,
        kind: TransactionKind = .standard,
        transferID: UUID? = nil,
        account: Account? = nil,
        category: Category? = nil,
        parentTransaction: Transaction? = nil,
        tags: [TransactionTag]? = nil,
        isDemoData: Bool = false
    ) {
        self.date = date
        self.payee = payee
        self.amount = amount
        self.memo = memo
        self.statusRawValue = status.rawValue
        self.kindRawValue = kind.rawValue
        self.transferID = transferID
        self.account = account
        self.category = category
        self.parentTransaction = parentTransaction
        self.tags = tags
        self.isDemoData = isDemoData
    }
}

@Model
final class TransactionHistoryEntry {
    var timestamp: Date
    var detail: String
    
    @Relationship(inverse: \Transaction.historyEntries)
    var transaction: Transaction?
    
    init(timestamp: Date = Date(), detail: String, transaction: Transaction? = nil) {
        self.timestamp = timestamp
        self.detail = detail
        self.transaction = transaction
    }
}

enum TransactionStatus: String, Codable, CaseIterable {
    case cleared = "Cleared"
    case uncleared = "Uncleared"
    case reconciled = "Reconciled"
}

enum TransactionKind: String, Codable, CaseIterable {
    case standard = "Standard"
    case transfer = "Transfer"
    case adjustment = "Adjustment"
    case ignored = "Ignored"
}
