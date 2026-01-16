import Foundation
import SwiftData

final class DeleteTransferCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let transferID: UUID
    private var savedData: [TransactionSnapshot] = []

    init(modelContext: ModelContext, transferID: UUID) {
        self.modelContext = modelContext
        self.transferID = transferID
        self.description = "Delete Transfer"
    }

    @MainActor
    func execute() throws {
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.transferID == id }
        )
        let transactions = try modelContext.fetch(descriptor)
        guard !transactions.isEmpty else {
            throw UndoRedoError.commandExecutionFailed("Transfer not found")
        }

        savedData = transactions.map(TransactionSnapshot.init(from:))
        for snapshot in savedData {
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: snapshot)
        }
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        try modelContext.save()
        DataChangeTracker.bump()
    }

    @MainActor
    func undo() throws {
        guard !savedData.isEmpty else {
            throw UndoRedoError.commandExecutionFailed("No saved data to restore")
        }

        for snapshot in savedData {
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: snapshot)
            let transaction = Transaction(
                date: snapshot.date,
                payee: snapshot.payee,
                amount: snapshot.amount,
                memo: snapshot.memo,
                status: snapshot.status,
                kind: snapshot.kind,
                transferID: snapshot.transferID,
                isDemoData: snapshot.isDemoData
            )

            if let accountID = snapshot.accountPersistentID,
               let account = modelContext.model(for: accountID) as? Account {
                transaction.account = account
            }

            if let categoryID = snapshot.categoryPersistentID,
               let category = modelContext.model(for: categoryID) as? Category {
                transaction.category = category
            }

            modelContext.insert(transaction)
            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
        }

        try modelContext.save()
        DataChangeTracker.bump()
    }
}
