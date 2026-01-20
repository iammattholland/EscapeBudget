import Foundation
import SwiftData

// MARK: - Add Transaction Command

final class AddTransactionCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var transaction: Transaction?
    private let date: Date
    private let payee: String
    private let amount: Decimal
    private let memo: String?
    private let status: TransactionStatus
    private let kind: TransactionKind
    private let transferID: UUID?
    private let accountPersistentID: PersistentIdentifier?
    private let categoryPersistentID: PersistentIdentifier?
    private let isDemoData: Bool

    init(
        modelContext: ModelContext,
        date: Date,
        payee: String,
        amount: Decimal,
        memo: String? = nil,
        status: TransactionStatus = .uncleared,
        kind: TransactionKind = .standard,
        transferID: UUID? = nil,
        account: Account? = nil,
        category: Category? = nil,
        isDemoData: Bool = false
    ) {
        self.modelContext = modelContext
        self.date = date
        self.payee = payee
        self.amount = amount
        self.memo = memo
        self.status = status
        self.kind = kind
        self.transferID = transferID
        self.accountPersistentID = account?.persistentModelID
        self.categoryPersistentID = category?.persistentModelID
        self.isDemoData = isDemoData
        self.description = "Add Transaction: \(payee)"
    }

    @MainActor
    func execute() throws {
        let newTransaction = Transaction(
            date: date,
            payee: payee,
            amount: amount,
            memo: memo,
            status: status,
            kind: kind,
            transferID: transferID,
            isDemoData: isDemoData
        )

        // Restore relationships
        if let accountID = accountPersistentID,
           let account = modelContext.model(for: accountID) as? Account {
            newTransaction.account = account
        }

        if let categoryID = categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            newTransaction.category = category
        }

        modelContext.insert(newTransaction)
        transaction = newTransaction

        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transaction: newTransaction)
        DataChangeTracker.bump()
    }

    @MainActor
    func undo() throws {
        guard let transaction = transaction else {
            throw UndoRedoError.commandExecutionFailed("Transaction not found")
        }

        let old = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)
        modelContext.delete(transaction)
        try modelContext.save()
        DataChangeTracker.bump()
        self.transaction = nil
    }
}

// MARK: - Delete Transaction Command

final class DeleteTransactionCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var transactionPersistentID: PersistentIdentifier
    private var savedData: TransactionSnapshot?

    init(modelContext: ModelContext, transaction: Transaction) {
        self.modelContext = modelContext
        self.transactionPersistentID = transaction.persistentModelID
        self.description = "Delete Transaction: \(transaction.payee)"
    }

    @MainActor
    func execute() throws {
        guard let transaction = modelContext.model(for: transactionPersistentID) as? Transaction else {
            throw UndoRedoError.commandExecutionFailed("Transaction not found")
        }

        // Save data for undo
        savedData = TransactionSnapshot(from: transaction)
        if let savedData {
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: savedData)
        }

        modelContext.delete(transaction)
        try modelContext.save()
        DataChangeTracker.bump()
    }

    @MainActor
    func undo() throws {
        guard let snapshot = savedData else {
            throw UndoRedoError.commandExecutionFailed("No saved data to restore")
        }

        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: snapshot)
        let newTransaction = Transaction(
            date: snapshot.date,
            payee: snapshot.payee,
            amount: snapshot.amount,
            memo: snapshot.memo,
            status: snapshot.status,
            kind: snapshot.kind,
            transferID: snapshot.transferID,
            isDemoData: snapshot.isDemoData
        )

        // Restore relationships
        if let accountID = snapshot.accountPersistentID,
           let account = modelContext.model(for: accountID) as? Account {
            newTransaction.account = account
        }

        if let categoryID = snapshot.categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            newTransaction.category = category
        }

        modelContext.insert(newTransaction)
        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transaction: newTransaction)
        DataChangeTracker.bump()

        // Update the persistent ID to the newly created transaction
        // so redo can find it
        transactionPersistentID = newTransaction.persistentModelID
    }
}

// MARK: - Update Transaction Command

final class UpdateTransactionCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let transactionPersistentID: PersistentIdentifier
    private let oldSnapshot: TransactionSnapshot
    private let newSnapshot: TransactionSnapshot

    init(
        modelContext: ModelContext,
        transaction: Transaction,
        newDate: Date,
        newPayee: String,
        newAmount: Decimal,
        newMemo: String?,
        newStatus: TransactionStatus,
        newAccount: Account?,
        newCategory: Category?,
        newKind: TransactionKind? = nil,
        newTransferID: UUID? = nil
    ) {
        self.modelContext = modelContext
        self.transactionPersistentID = transaction.persistentModelID
        self.oldSnapshot = TransactionSnapshot(from: transaction)
        self.newSnapshot = TransactionSnapshot(
            date: newDate,
            payee: newPayee,
            amount: newAmount,
            memo: newMemo,
            status: newStatus,
            kind: newKind ?? transaction.kind,
            transferID: newTransferID ?? transaction.transferID,
            accountPersistentID: newAccount?.persistentModelID,
            categoryPersistentID: newCategory?.persistentModelID,
            isDemoData: transaction.isDemoData
        )
        self.description = "Update Transaction: \(transaction.payee)"
    }

    @MainActor
    func execute() throws {
        guard let transaction = modelContext.model(for: transactionPersistentID) as? Transaction else {
            throw UndoRedoError.commandExecutionFailed("Transaction not found")
        }

        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)
        applySnapshot(newSnapshot, to: transaction)
        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: newSnapshot)
        DataChangeTracker.bump()
    }

    @MainActor
    func undo() throws {
        guard let transaction = modelContext.model(for: transactionPersistentID) as? Transaction else {
            throw UndoRedoError.commandExecutionFailed("Transaction not found")
        }

        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: newSnapshot)
        applySnapshot(oldSnapshot, to: transaction)
        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)
        DataChangeTracker.bump()
    }

    private func applySnapshot(_ snapshot: TransactionSnapshot, to transaction: Transaction) {
        transaction.date = snapshot.date
        transaction.payee = snapshot.payee
        transaction.amount = snapshot.amount
        transaction.memo = snapshot.memo
        transaction.status = snapshot.status
        transaction.kind = snapshot.kind
        transaction.transferID = snapshot.transferID

        if let accountID = snapshot.accountPersistentID,
           let account = modelContext.model(for: accountID) as? Account {
            transaction.account = account
        } else {
            transaction.account = nil
        }

        if let categoryID = snapshot.categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            transaction.category = category
        } else {
            transaction.category = nil
        }
    }
}

// MARK: - Transaction Snapshot

struct TransactionSnapshot {
    let date: Date
    let payee: String
    let amount: Decimal
    let memo: String?
    let status: TransactionStatus
    let kind: TransactionKind
    let transferID: UUID?
    let accountPersistentID: PersistentIdentifier?
    let categoryPersistentID: PersistentIdentifier?
    let isDemoData: Bool

    init(from transaction: Transaction) {
        self.date = transaction.date
        self.payee = transaction.payee
        self.amount = transaction.amount
        self.memo = transaction.memo
        self.status = transaction.status
        self.kind = transaction.kind
        self.transferID = transaction.transferID
        self.accountPersistentID = transaction.account?.persistentModelID
        self.categoryPersistentID = transaction.category?.persistentModelID
        self.isDemoData = transaction.isDemoData
    }

    init(
        date: Date,
        payee: String,
        amount: Decimal,
        memo: String?,
        status: TransactionStatus,
        kind: TransactionKind,
        transferID: UUID?,
        accountPersistentID: PersistentIdentifier?,
        categoryPersistentID: PersistentIdentifier?,
        isDemoData: Bool
    ) {
        self.date = date
        self.payee = payee
        self.amount = amount
        self.memo = memo
        self.status = status
        self.kind = kind
        self.transferID = transferID
        self.accountPersistentID = accountPersistentID
        self.categoryPersistentID = categoryPersistentID
        self.isDemoData = isDemoData
    }
}
