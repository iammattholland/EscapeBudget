import Foundation
import SwiftData

@MainActor
enum TransferLinker {
    enum SearchWindow: Hashable {
        case days(Int)
        case all

        var maxInterval: TimeInterval? {
            switch self {
            case .days(let days):
                return TimeInterval(days) * 24 * 60 * 60
            case .all:
                return nil
            }
        }
    }

    static func candidateMatches(
        for base: Transaction,
        modelContext: ModelContext,
        window: SearchWindow = .days(90),
        fetchLimit: Int = 500
    ) -> [Transaction] {
        let maxInterval = window.maxInterval
        let oppositeAmount = -base.amount

        var descriptor: FetchDescriptor<Transaction>
        if let maxInterval {
            let startDate = base.date.addingTimeInterval(-maxInterval)
            let endDate = base.date.addingTimeInterval(maxInterval)
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { t in
                    t.transferID == nil &&
                    t.date >= startDate &&
                    t.date <= endDate
                }
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { t in
                    t.transferID == nil
                }
            )
        }
        descriptor.fetchLimit = fetchLimit

        let fetched = (try? modelContext.fetch(descriptor)) ?? []

        // Filter candidates
        let filtered = fetched.filter { candidate in
            // Must be different transaction
            guard candidate.persistentModelID != base.persistentModelID else { return false }

            // Must be different account
            guard candidate.account?.persistentModelID != base.account?.persistentModelID else { return false }

            // Filter by kind (standard or transfer, but not ignored)
            guard candidate.kind == .standard || candidate.kind == .transfer else { return false }

            // For strict matches, require exact opposite amount
            // For flexible matches, allow similar amounts (within 1% tolerance)
            let tolerance: Decimal = 0.01  // 1% tolerance
            let amountDiff = abs(candidate.amount + base.amount)
            let avgAmount = (abs(candidate.amount) + abs(base.amount)) / 2

            // If amounts are exact opposites, definitely include
            if candidate.amount == oppositeAmount {
                return true
            }

            // If amounts are very close (within tolerance), include
            if avgAmount > 0 && amountDiff / avgAmount <= tolerance {
                return true
            }

            return false
        }

        // Sort by closest date first, then by account name
        return filtered.sorted {
            let leftDelta = abs($0.date.timeIntervalSince(base.date))
            let rightDelta = abs($1.date.timeIntervalSince(base.date))
            if leftDelta != rightDelta { return leftDelta < rightDelta }

            let leftName = $0.account?.name ?? ""
            let rightName = $1.account?.name ?? ""
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    static func linkAsTransfer(
        base: Transaction,
        match: Transaction,
        modelContext: ModelContext,
        wasAutoDetected: Bool = false
    ) throws {
        let baseOld = TransactionSnapshot(from: base)
        let matchOld = TransactionSnapshot(from: match)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: baseOld)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: matchOld)

        guard base.transferID == nil, match.transferID == nil else {
            throw UndoRedoError.commandExecutionFailed("Transaction is already part of a transfer")
        }
        guard base.amount == -match.amount else {
            throw UndoRedoError.commandExecutionFailed("Transfer amounts must be equal and opposite")
        }
        guard base.account?.persistentModelID != match.account?.persistentModelID else {
            throw UndoRedoError.commandExecutionFailed("Transfer accounts must be different")
        }

        let id = UUID()
        logConvertedToTransfer(base, other: match, modelContext: modelContext)
        logConvertedToTransfer(match, other: base, modelContext: modelContext)
        applyTransferFields(transaction: base, transferID: id)
        applyTransferFields(transaction: match, transferID: id)

        // Learn from this confirmation
        let debit = base.amount < 0 ? base : match
        let credit = base.amount > 0 ? base : match
        let learner = TransferPatternLearner(modelContext: modelContext)
        learner.learnFromConfirmation(debit: debit, credit: credit, wasAutoDetected: wasAutoDetected)

        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transaction: base)
        TransactionStatsUpdateCoordinator.markDirty(transaction: match)
        DataChangeTracker.bump()
    }

    private static func applyTransferFields(transaction: Transaction, transferID: UUID) {
        transaction.kind = .transfer
        transaction.transferID = transferID
        transaction.category = nil
        transaction.transferInboxDismissed = false
    }

    static func markUnmatchedTransfer(_ transaction: Transaction, modelContext: ModelContext) throws {
        let old = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

        guard transaction.transferID == nil else {
            throw UndoRedoError.commandExecutionFailed("This transfer is already linked.")
        }
        logHistory(
            for: transaction,
            detail: "Marked as Transfer (unmatched). Previous payee was “\(transaction.payee)”; previous category was \(transaction.category?.name ?? "Uncategorized").",
            modelContext: modelContext
        )
        transaction.kind = .transfer
        transaction.category = nil
        transaction.transferInboxDismissed = false
        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
        DataChangeTracker.bump()
    }

    static func convertToStandard(_ transaction: Transaction, modelContext: ModelContext) throws {
        let old = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

        guard transaction.transferID == nil else {
            throw UndoRedoError.commandExecutionFailed("Linked transfers can’t be converted here.")
        }
        logHistory(
            for: transaction,
            detail: "Converted from Transfer back to Standard.",
            modelContext: modelContext
        )
        transaction.kind = .standard
        transaction.category = nil
        transaction.transferInboxDismissed = false
        try modelContext.save()
        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
        DataChangeTracker.bump()
    }

    private static func logConvertedToTransfer(_ transaction: Transaction, other: Transaction, modelContext: ModelContext) {
        let otherAccount = other.account?.name ?? "Other account"
        let detail = "Converted to Transfer with \(otherAccount). Previous payee was “\(transaction.payee)”; previous category was \(transaction.category?.name ?? "Uncategorized")."
        logHistory(for: transaction, detail: detail, modelContext: modelContext)
    }

    /// Learn from a rejected transfer suggestion
    static func learnFromRejection(
        base: Transaction,
        match: Transaction,
        modelContext: ModelContext
    ) {
        let debit = base.amount < 0 ? base : match
        let credit = base.amount > 0 ? base : match
        let learner = TransferPatternLearner(modelContext: modelContext)
        learner.learnFromRejection(debit: debit, credit: credit, wasAutoSuggested: true)
    }

    private static func logHistory(for transaction: Transaction, detail: String, modelContext: ModelContext) {
        TransactionHistoryService.append(detail: detail, to: transaction, in: modelContext)
    }
}
