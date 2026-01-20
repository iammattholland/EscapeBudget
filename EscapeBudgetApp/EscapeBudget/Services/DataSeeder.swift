import Foundation
import SwiftData
import os.log

final class DataSeeder {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget", category: "DataSeeder")

    static func ensureSystemGroups(context: ModelContext, persistChanges: Bool = true) {
        // Check if Income group exists
        let incomeType = CategoryGroupType.income.rawValue
        let incomeDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == incomeType })

        do {
            let incomeResults = try context.fetch(incomeDescriptor)
            if incomeResults.isEmpty {
                // Create Income group - Order -1 to ensure it's at the top
                let incomeGroup = CategoryGroup(name: "Income", order: -1, type: .income)
                incomeGroup.categories = []
                context.insert(incomeGroup)
                logger.info("Created default Income category group")
            }
        } catch {
            logger.error("Failed to ensure Income group: \(error, privacy: .private)")
        }

        // Check if Transfer group exists
        let transferType = CategoryGroupType.transfer.rawValue
        let transferDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == transferType })

        do {
            let transferResults = try context.fetch(transferDescriptor)
            if transferResults.isEmpty {
                // Create Transfer group - Order -2 to ensure it's at the very top
                let transferGroup = CategoryGroup(name: "Transfer", order: -2, type: .transfer)

                // Add a default "Transfer" category
                let transferCategory = Category(name: "Transfer", assigned: 0, activity: 0, order: 0)
                transferGroup.categories = [transferCategory]
                context.insert(transferGroup)
                logger.info("Created default Transfer category group")
            }
        } catch {
            logger.error("Failed to ensure Transfer group: \(error, privacy: .private)")
        }

        normalizeTransferTransactions(context: context)
        if persistChanges {
            context.safeSave(context: "DataSeeder.ensureSystemGroups", showErrorToUser: false)
        }
    }

    private static func normalizeTransferTransactions(context: ModelContext) {
        let transferType = CategoryGroupType.transfer.rawValue
        let transferKind = TransactionKind.transfer.rawValue

	        do {
	            // Legacy/imported data sometimes categorizes transactions under the "Transfer" group
	            // without setting the transaction kind. Convert those to transfers so they don't count
	            // as income/expense and can be matched later.
	            // SwiftData predicates don't support optional-chained relationship traversal here,
	            // so fetch transactions with a category and filter in memory.
	            let withCategory = FetchDescriptor<Transaction>(
	                predicate: #Predicate { $0.category != nil }
	            )
	            let categorized = try context.fetch(withCategory)
	            for transaction in categorized where transaction.category?.group?.typeRawValue == transferType {
	                transaction.kind = .transfer
	                transaction.category = nil
	            }

            let transferWithCategory = FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.kindRawValue == transferKind && $0.category != nil
                }
            )
            let transferCategoryResults = try context.fetch(transferWithCategory)
            for transaction in transferCategoryResults {
                transaction.category = nil
            }
        } catch {
            logger.error("Failed to normalize transfer transactions: \(error, privacy: .private)")
        }
    }
    
    static func seedDemoNotifications(context: ModelContext) {
        let notifications = [
            AppNotification(
                title: "Welcome to Escape Budget!",
                message: "Your journey to financial freedom starts here. Set up your budget to get started.",
                date: Date(),
                type: .success,
                isRead: false
            ),
            AppNotification(
                title: "Budget Alert",
                message: "You've used 80% of your Dining Out budget for this month.",
                date: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!,
                type: .warning,
                isRead: false
            ),
            AppNotification(
                title: "Bill Reminder",
                message: "Netflix subscription payment of $15.99 is due tomorrow.",
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                type: .info,
                isRead: true
            ),
            AppNotification(
                title: "Goal Reached! 🚀",
                message: "Congratulations! You've reached your savings goal for 'Emergency Fund'.",
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
                type: .success,
                isRead: true
            ),
            AppNotification(
                title: "Overspending Alert",
                message: "You have exceeded your Shopping budget by $50.00.",
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
                type: .alert,
                isRead: true
            )
        ]
        
        for notification in notifications {
            notification.isDemoData = true
            context.insert(notification)
        }
        
        // Update the badge state
        UserDefaults.standard.set(true, forKey: "hasNotifications")
    }
}
