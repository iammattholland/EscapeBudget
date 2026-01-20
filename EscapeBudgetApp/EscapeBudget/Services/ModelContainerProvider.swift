import Foundation
import os.log
import SwiftData

enum ModelContainerProvider {
    private static let schema = Schema([
        Account.self,
        CategoryGroup.self,
        Category.self,
        Transaction.self,
        TransactionTag.self,
        TransactionHistoryEntry.self,
        PurchasedItem.self,
        MonthlyAccountTotal.self,
        MonthlyCashflowTotal.self,
        SavingsGoal.self,
        PurchasePlan.self,
        RecurringPurchase.self,
        CustomDashboardWidget.self,
        AppNotification.self,
        AutoRule.self,
        AutoRuleApplication.self,
        TransferPattern.self,
        CategoryPattern.self,
        PayeePattern.self,
        RecurringPattern.self,
        BudgetForecast.self,
        DiagnosticEvent.self,
        ReceiptImage.self,
        DebtAccount.self
    ])

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget",
        category: "Persistence"
    )

    static func makeContainer(demoMode: Bool, iCloudSyncEnabled: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        let isUITesting = ProcessInfo.processInfo.arguments.contains("ui_testing")

        // Use separate persistent storage for demo mode to avoid conflicts with user data
        if demoMode {
            // UI tests need a clean, deterministic store across runs.
            configuration = ModelConfiguration("demo", schema: schema, isStoredInMemoryOnly: isUITesting, cloudKitDatabase: .none)
        } else {
            if iCloudSyncEnabled {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            } else {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            }
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            applyStoreProtectionIfPresent(demoMode: demoMode)
            return container
        } catch {
            logger.error("SwiftData store load failed: \(String(describing: error), privacy: .private)")

            guard shouldAttemptRecovery(for: error, demoMode: demoMode),
                  recoverPersistentStoreArtifacts(demoMode: demoMode) else {
                throw error
            }

            logger.error("Recovered corrupted SwiftData store. Recreating container.")
            let container = try ModelContainer(for: schema, configurations: [configuration])
            applyStoreProtectionIfPresent(demoMode: demoMode)
            return container
        }
    }

    private static func shouldAttemptRecovery(for error: Error, demoMode: Bool) -> Bool {
        guard !demoMode else { return false }
        let description = String(describing: error)
        return description.contains("loadIssueModelContainer")
    }

    @discardableResult
    private static func recoverPersistentStoreArtifacts(demoMode: Bool) -> Bool {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }

        let storePrefix = demoMode ? "demo" : "default"
        let filenames = ["\(storePrefix).store", "\(storePrefix).store-wal", "\(storePrefix).store-shm"]
        var removedAnything = false

        for filename in filenames {
            let url = supportDirectory.appendingPathComponent(filename, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    removedAnything = true
                } catch {
                    SecurityLogger.shared.logFileOperationError(operation: "delete", path: url.path)
                }
            }
        }

        return removedAnything
    }

    private static func applyStoreProtectionIfPresent(demoMode: Bool) {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let storePrefix = demoMode ? "demo" : "default"
        let filenames = ["\(storePrefix).store", "\(storePrefix).store-wal", "\(storePrefix).store-shm"]

        for filename in filenames {
            let url = supportDirectory.appendingPathComponent(filename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        }
    }
}
