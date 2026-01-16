import Foundation
import SwiftData

@MainActor
enum ReconcileReminderService {
    private static let thresholdsDays: [Int] = [30, 60, 90]

    static func maybePostOverdueReconcileReminders(modelContext: ModelContext) {
        let accounts = (try? modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.name)]))) ?? []
        guard !accounts.isEmpty else { return }

        let now = Date()
        var didBackfillCreatedAt = false

        for account in accounts {
            if account.isDemoData { continue }
            if account.isTrackingOnly { continue }

            if account.createdAt == nil {
                account.createdAt = now
                didBackfillCreatedAt = true
            }

            let lastReconciled = effectiveLastReconciledAt(for: account, modelContext: modelContext)
            let anchorDate = lastReconciled ?? account.createdAt
            guard let anchorDate else { continue }

            let isNeverReconciled = (lastReconciled == nil)

            let daysSince = daysBetween(anchorDate, now)
            guard let threshold = thresholdsDays.last(where: { daysSince >= $0 }) else { continue }

            let alreadySent = account.reconcileReminderLastThresholdSent ?? 0
            guard threshold > alreadySent else { continue }

            let accountKey = String(describing: account.persistentModelID)
            let cycleToken = cycleTokenForAnchor(anchorDate)
            let dedupeKey = "reconcile.reminder.\(accountKey).\(threshold).\(cycleToken)"
            let headline = isNeverReconciled ? "Reconcile Reminder" : "Reconcile Reminder"
            let message: String = {
                if isNeverReconciled {
                    return "It’s been over \(threshold) days since you started using \(account.name) without reconciling. Open the account and reconcile to keep balances accurate."
                }
                return "It’s been over \(threshold) days since you reconciled \(account.name). Open the account and reconcile to keep balances accurate."
            }()

            InAppNotificationService.post(
                title: headline,
                message: message,
                type: .warning,
                in: modelContext,
                topic: .reconcileReminders,
                dedupeKey: dedupeKey,
                minimumInterval: nil
            )

            account.reconcileReminderLastThresholdSent = threshold
        }

        if didBackfillCreatedAt {
            modelContext.safeSave(context: "ReconcileReminderService.backfillCreatedAt", showErrorToUser: false)
        } else {
            // Persist reminder milestone updates (silent; ok if it fails).
            modelContext.safeSave(context: "ReconcileReminderService.updateMilestones", showErrorToUser: false)
        }
    }

    private static func effectiveLastReconciledAt(for account: Account, modelContext: ModelContext) -> Date? {
        if let stored = account.lastReconciledAt { return stored }

        // Backward-compat: infer from the newest reconciled adjustment transaction.
        let kindRaw = "Adjustment"
        let statusRaw = "Reconciled"
        let accountID = account.persistentModelID

        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.account?.persistentModelID == accountID &&
                tx.kindRawValue == kindRaw &&
                tx.statusRawValue == statusRaw
            },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first?.date
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func cycleTokenForAnchor(_ anchor: Date) -> Int {
        Int(floor(anchor.timeIntervalSince1970 / (24 * 60 * 60)))
    }
}
