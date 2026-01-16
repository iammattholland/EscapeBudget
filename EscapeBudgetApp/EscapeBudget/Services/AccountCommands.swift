import Foundation
import SwiftData

// MARK: - Add Account Command

class AddAccountCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var account: Account?
    private let name: String
    private let type: AccountType
    private let balance: Decimal
    private let notes: String?
    private let isTrackingOnly: Bool
    private let lastReconciledAt: Date?
    private let createdAt: Date?
    private let reconcileReminderLastThresholdSent: Int?
    private let isDemoData: Bool

    init(
        modelContext: ModelContext,
        name: String,
        type: AccountType,
        balance: Decimal = 0.0,
        notes: String? = nil,
        createdAt: Date? = Date(),
        isTrackingOnly: Bool = false,
        lastReconciledAt: Date? = nil,
        reconcileReminderLastThresholdSent: Int? = 0,
        isDemoData: Bool = false
    ) {
        self.modelContext = modelContext
        self.name = name
        self.type = type
        self.balance = balance
        self.notes = notes
        self.createdAt = createdAt
        self.isTrackingOnly = isTrackingOnly
        self.lastReconciledAt = lastReconciledAt
        self.reconcileReminderLastThresholdSent = reconcileReminderLastThresholdSent
        self.isDemoData = isDemoData
        self.description = "Add Account: \(name)"
    }

    @MainActor
    func execute() throws {
        let newAccount = Account(
            name: name,
            type: type,
            balance: balance,
            notes: notes,
            createdAt: createdAt,
            isTrackingOnly: isTrackingOnly,
            lastReconciledAt: lastReconciledAt,
            reconcileReminderLastThresholdSent: reconcileReminderLastThresholdSent,
            isDemoData: isDemoData
        )

        modelContext.insert(newAccount)
        account = newAccount

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(newAccount)
            account = nil
            throw error
        }
    }

    @MainActor
    func undo() throws {
        guard let account = account else {
            throw UndoRedoError.commandExecutionFailed("Account not found")
        }

        modelContext.delete(account)
        do {
            try modelContext.save()
            self.account = nil
        } catch {
            modelContext.insert(account)
            throw error
        }
    }
}

// MARK: - Delete Account Command

class DeleteAccountCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var accountPersistentID: PersistentIdentifier
    private var savedData: AccountSnapshot?

    init(modelContext: ModelContext, account: Account) {
        self.modelContext = modelContext
        self.accountPersistentID = account.persistentModelID
        self.description = "Delete Account: \(account.name)"
    }

    @MainActor
    func execute() throws {
        guard let account = modelContext.model(for: accountPersistentID) as? Account else {
            throw UndoRedoError.commandExecutionFailed("Account not found")
        }

        // Save data for undo
        savedData = AccountSnapshot(from: account)

        modelContext.delete(account)
        do {
            try modelContext.save()
        } catch {
            modelContext.insert(account)
            throw error
        }
    }

    @MainActor
    func undo() throws {
        guard let snapshot = savedData else {
            throw UndoRedoError.commandExecutionFailed("No saved data to restore")
        }

        let newAccount = Account(
            name: snapshot.name,
            type: snapshot.type,
            balance: snapshot.balance,
            notes: snapshot.notes,
            createdAt: snapshot.createdAt,
            isTrackingOnly: snapshot.isTrackingOnly,
            lastReconciledAt: snapshot.lastReconciledAt,
            reconcileReminderLastThresholdSent: snapshot.reconcileReminderLastThresholdSent,
            isDemoData: snapshot.isDemoData
        )

        modelContext.insert(newAccount)
        do {
            try modelContext.save()
            // Update the persistent ID to the newly created account
            accountPersistentID = newAccount.persistentModelID
        } catch {
            modelContext.delete(newAccount)
            throw error
        }
    }
}

// MARK: - Update Account Command

class UpdateAccountCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let accountPersistentID: PersistentIdentifier
    private let oldSnapshot: AccountSnapshot
    private let newSnapshot: AccountSnapshot

    init(
        modelContext: ModelContext,
        account: Account,
        newName: String,
        newType: AccountType,
        newBalance: Decimal,
        newNotes: String?,
        newIsTrackingOnly: Bool? = nil
    ) {
        self.modelContext = modelContext
        self.accountPersistentID = account.persistentModelID
        self.oldSnapshot = AccountSnapshot(from: account)
        self.newSnapshot = AccountSnapshot(
            name: newName,
            type: newType,
            balance: newBalance,
            notes: newNotes,
            isTrackingOnly: newIsTrackingOnly ?? account.isTrackingOnly,
            lastReconciledAt: account.lastReconciledAt,
            isDemoData: account.isDemoData
        )
        self.description = "Update Account: \(account.name)"
    }

    @MainActor
    func execute() throws {
        guard let account = modelContext.model(for: accountPersistentID) as? Account else {
            throw UndoRedoError.commandExecutionFailed("Account not found")
        }

        applySnapshot(newSnapshot, to: account)
        do {
            try modelContext.save()
        } catch {
            applySnapshot(oldSnapshot, to: account)
            throw error
        }
    }

    @MainActor
    func undo() throws {
        guard let account = modelContext.model(for: accountPersistentID) as? Account else {
            throw UndoRedoError.commandExecutionFailed("Account not found")
        }

        applySnapshot(oldSnapshot, to: account)
        do {
            try modelContext.save()
        } catch {
            applySnapshot(newSnapshot, to: account)
            throw error
        }
    }

    private func applySnapshot(_ snapshot: AccountSnapshot, to account: Account) {
        account.name = snapshot.name
        account.type = snapshot.type
        account.balance = snapshot.balance
        account.notes = snapshot.notes
        account.createdAt = snapshot.createdAt
        account.isTrackingOnly = snapshot.isTrackingOnly
        account.lastReconciledAt = snapshot.lastReconciledAt
        account.reconcileReminderLastThresholdSent = snapshot.reconcileReminderLastThresholdSent
    }
}

// MARK: - Account Snapshot

struct AccountSnapshot {
    let name: String
    let type: AccountType
    let balance: Decimal
    let notes: String?
    let createdAt: Date?
    let isTrackingOnly: Bool
    let lastReconciledAt: Date?
    let reconcileReminderLastThresholdSent: Int?
    let isDemoData: Bool

    init(from account: Account) {
        self.name = account.name
        self.type = account.type
        self.balance = account.balance
        self.notes = account.notes
        self.createdAt = account.createdAt
        self.isTrackingOnly = account.isTrackingOnly
        self.lastReconciledAt = account.lastReconciledAt
        self.reconcileReminderLastThresholdSent = account.reconcileReminderLastThresholdSent
        self.isDemoData = account.isDemoData
    }

    init(
        name: String,
        type: AccountType,
        balance: Decimal,
        notes: String?,
        createdAt: Date? = Date(),
        isTrackingOnly: Bool = false,
        lastReconciledAt: Date? = nil,
        reconcileReminderLastThresholdSent: Int? = 0,
        isDemoData: Bool
    ) {
        self.name = name
        self.type = type
        self.balance = balance
        self.notes = notes
        self.createdAt = createdAt
        self.isTrackingOnly = isTrackingOnly
        self.lastReconciledAt = lastReconciledAt
        self.reconcileReminderLastThresholdSent = reconcileReminderLastThresholdSent
        self.isDemoData = isDemoData
    }
}
