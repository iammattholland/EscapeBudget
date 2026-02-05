import Foundation
import SwiftData

struct EscapeBudgetBackup: Codable {
    struct AppInfo: Codable {
        var bundleIdentifier: String
        var version: String?
        var build: String?
    }

    struct Settings: Codable {
        var currencyCode: String?
        var userAppearance: String?
        var appIconMode: String?
        var appColorMode: String?
        var iCloudSyncEnabled: Bool?
        var showTransactionTags: Bool?
        var budgetAlerts: Bool?
        var billReminders: Bool?
        var transfersInboxNotifications: Bool?
        var importCompleteNotifications: Bool?
        var exportStatusNotifications: Bool?
        var backupRestoreNotifications: Bool?
        var ruleAppliedNotifications: Bool?
        var badgeAchievementNotifications: Bool?
        var showSensitiveNotificationContent: Bool?
        var billReminderDays: Int?
        var appLanguage: String?
        var weekStartDay: String?
        var relockAfterBackground: Bool?
        var normalizePayeeOnImport: Bool?
        var applyAutoRulesOnImport: Bool?
        var detectDuplicatesOnImport: Bool?
        var suggestTransfersOnImport: Bool?
        var saveProcessingHistory: Bool?
        var cashflowHorizonDays: Int?
        var cashflowIncludeIncome: Bool?
        var cashflowMonthlyIncome: Double?
        var cashflowIncludeChequing: Bool?
        var cashflowIncludeSavings: Bool?
        var cashflowIncludeOtherCash: Bool?
        var retirement: RetirementSettings?
    }

    struct RetirementSettings: Codable {
        var isConfigured: Bool?
        var scenario: String?
        var currentAge: Int?
        var targetAge: Int?
        var includeInvestmentAccounts: Bool?
        var includeSavingsAccounts: Bool?
        var includeOtherPositiveAccounts: Bool?
        var useSpendingFromTransactions: Bool?
        var spendingMonthlyOverride: String?
        var useInferredContributions: Bool?
        var monthlyContributionOverride: String?
        var externalAssets: String?
        var otherIncomeMonthly: String?
        var useManualTarget: Bool?
        var manualTarget: String?
        var safeWithdrawalRate: Double?
        var realReturn: Double?
        var showAdvanced: Bool?
    }

    struct AccountSnapshot: Codable {
        var id: UUID
        var name: String
        var typeRawValue: String
        var balance: Decimal
        var notes: String?
        var isTrackingOnly: Bool?
        var lastReconciledAt: Date?
        var createdAt: Date?
        var reconcileReminderLastThresholdSent: Int?
        var isDemoData: Bool
    }

    struct CategoryGroupSnapshot: Codable {
        var id: UUID
        var name: String
        var order: Int
        var typeRawValue: String
        var isDemoData: Bool
    }

    struct CategorySnapshot: Codable {
        var id: UUID
        var name: String
        var assigned: Decimal
        var activity: Decimal
        var order: Int
        var groupID: UUID?
        var savingsGoalID: UUID?
        var icon: String?
        var memo: String?
        var isDemoData: Bool
    }

    struct TransactionTagSnapshot: Codable {
        var id: UUID
        var name: String
        var colorHex: String
        var order: Int
        var isDemoData: Bool
    }

    struct SavingsGoalSnapshot: Codable {
        var id: UUID
        var name: String
        var targetAmount: Decimal
        var currentAmount: Decimal
        var targetDate: Date?
        var monthlyContribution: Decimal?
        var colorHex: String
        var notes: String?
        var isAchieved: Bool
        var createdDate: Date
        var categoryID: UUID?
        var isDemoData: Bool
    }

    struct TransactionSnapshot: Codable {
        var id: UUID
        var date: Date
        var payee: String
        var amount: Decimal
        var memo: String?
        var statusRawValue: String
        var kindRawValue: String
        var transferID: UUID?
        var transferInboxDismissed: Bool
        var externalTransferLabel: String?
        var accountID: UUID?
        var categoryID: UUID?
        var tagIDs: [UUID]
        var parentID: UUID?
        var isDemoData: Bool
    }

    struct TransactionHistoryEntrySnapshot: Codable {
        var id: UUID
        var timestamp: Date
        var detail: String
        var transactionID: UUID?
    }

    struct PurchasedItemSnapshot: Codable {
        var id: UUID
        var name: String
        var price: Decimal
        var note: String?
        var order: Int
        var createdAt: Date
        var transactionID: UUID?
        var isDemoData: Bool
    }

    struct AutoRuleSnapshot: Codable {
        var id: UUID
        var name: String
        var isEnabled: Bool
        var order: Int
        var createdAt: Date
        var updatedAt: Date
        var matchPayeeConditionRaw: String?
        var matchPayeeValue: String?
        var matchPayeeCaseSensitive: Bool
        var matchAccountID: UUID?
        var matchAmountConditionRaw: String?
        var matchAmountValue: Decimal?
        var matchAmountValueMax: Decimal?
        var actionRenamePayee: String?
        var actionCategoryID: UUID?
        var actionTagIDs: [UUID]
        var actionMemo: String?
        var actionAppendMemo: Bool
        var actionStatusRaw: String?
        var timesApplied: Int
        var lastAppliedAt: Date?
    }

    struct AutoRuleApplicationSnapshot: Codable {
        var id: UUID
        var appliedAt: Date
        var fieldChanged: String
        var oldValue: String?
        var newValue: String?
        var wasOverridden: Bool
        var ruleID: UUID?
        var transactionID: UUID?
    }

    struct RecurringPurchaseSnapshot: Codable {
        var id: UUID
        var name: String
        var amount: Decimal
        var frequency: String
        var nextDate: Date
        var category: String
        var notes: String?
        var isActive: Bool
        var createdDate: Date
        var isDemoData: Bool
    }

    struct PurchasePlanSnapshot: Codable {
        var id: UUID
        var itemName: String
        var expectedPrice: Decimal
        var purchaseDate: Date?
        var url: String?
        var category: String
        var priority: Int
        var notes: String?
        var imageData: Data?
        var isPurchased: Bool
        var actualPrice: Decimal?
        var actualPurchaseDate: Date?
        var createdDate: Date
        var isDemoData: Bool
    }

    struct CustomDashboardWidgetSnapshot: Codable {
        var id: UUID
        var title: String
        var order: Int
        var widgetType: WidgetType
        var chartType: ChartType
        var dataType: WidgetDataType
        var dateRange: WidgetDateRange
        var isDemoData: Bool
    }

    struct AppNotificationSnapshot: Codable {
        var id: UUID
        var title: String
        var message: String
        var date: Date
        var isRead: Bool
        var type: NotificationType
        var isDemoData: Bool
    }

    var format: String
    var version: Int
    var exportedAt: Date
    var app: AppInfo
    var settings: Settings

    var accounts: [AccountSnapshot]
    var categoryGroups: [CategoryGroupSnapshot]
    var categories: [CategorySnapshot]
    var tags: [TransactionTagSnapshot]
    var savingsGoals: [SavingsGoalSnapshot]
    var transactions: [TransactionSnapshot]
    var transactionHistoryEntries: [TransactionHistoryEntrySnapshot]
    var purchasedItems: [PurchasedItemSnapshot] = []
    var autoRules: [AutoRuleSnapshot]
    var autoRuleApplications: [AutoRuleApplicationSnapshot]
    var recurringPurchases: [RecurringPurchaseSnapshot]
    var purchasePlans: [PurchasePlanSnapshot]
    var customDashboardWidgets: [CustomDashboardWidgetSnapshot]
    var notifications: [AppNotificationSnapshot]
}

enum EscapeBudgetBackupService {
    static let currentVersion = 1
    static let formatIdentifier = "EscapeBudgetBackup"

    static func makeBackup(modelContext: ModelContext) throws -> EscapeBudgetBackup {
        let accounts = try modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.name)]))
        let categoryGroups = try modelContext.fetch(FetchDescriptor<CategoryGroup>(sortBy: [SortDescriptor(\CategoryGroup.order)]))
        let categories = try modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.order)]))
        let tags = try modelContext.fetch(FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\TransactionTag.order)]))
        let goals = try modelContext.fetch(FetchDescriptor<SavingsGoal>(sortBy: [SortDescriptor(\SavingsGoal.createdDate)]))
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]))
        let historyEntries = try modelContext.fetch(FetchDescriptor<TransactionHistoryEntry>(sortBy: [SortDescriptor(\TransactionHistoryEntry.timestamp)]))
        let purchasedItems = try modelContext.fetch(FetchDescriptor<PurchasedItem>(sortBy: [SortDescriptor(\PurchasedItem.order), SortDescriptor(\PurchasedItem.createdAt)]))
        let autoRules = try modelContext.fetch(FetchDescriptor<AutoRule>(sortBy: [SortDescriptor(\AutoRule.order)]))
        let autoRuleApplications = try modelContext.fetch(FetchDescriptor<AutoRuleApplication>(sortBy: [SortDescriptor(\AutoRuleApplication.appliedAt)]))
        let recurring = try modelContext.fetch(FetchDescriptor<RecurringPurchase>(sortBy: [SortDescriptor(\RecurringPurchase.createdDate)]))
        let plans = try modelContext.fetch(FetchDescriptor<PurchasePlan>(sortBy: [SortDescriptor(\PurchasePlan.createdDate)]))
        let widgets = try modelContext.fetch(FetchDescriptor<CustomDashboardWidget>(sortBy: [SortDescriptor(\CustomDashboardWidget.order)]))
        let notifications = try modelContext.fetch(FetchDescriptor<AppNotification>(sortBy: [SortDescriptor(\AppNotification.date)]))

        var accountIDs: [PersistentIdentifier: UUID] = [:]
        for account in accounts { accountIDs[account.persistentModelID] = UUID() }

        var groupIDs: [PersistentIdentifier: UUID] = [:]
        for group in categoryGroups { groupIDs[group.persistentModelID] = UUID() }

        var categoryIDs: [PersistentIdentifier: UUID] = [:]
        for category in categories { categoryIDs[category.persistentModelID] = UUID() }

        var tagIDs: [PersistentIdentifier: UUID] = [:]
        for tag in tags { tagIDs[tag.persistentModelID] = UUID() }

        var goalIDs: [PersistentIdentifier: UUID] = [:]
        for goal in goals { goalIDs[goal.persistentModelID] = UUID() }

        var transactionIDs: [PersistentIdentifier: UUID] = [:]
        for transaction in transactions { transactionIDs[transaction.persistentModelID] = UUID() }

        let accountSnapshots = accounts.compactMap { account -> EscapeBudgetBackup.AccountSnapshot? in
            guard let id = accountIDs[account.persistentModelID] else { return nil }
            return .init(
                id: id,
                name: account.name,
                typeRawValue: account.typeRawValue,
                balance: account.balance,
                notes: account.notes,
                isTrackingOnly: account.isTrackingOnly,
                lastReconciledAt: account.lastReconciledAt,
                createdAt: account.createdAt,
                reconcileReminderLastThresholdSent: account.reconcileReminderLastThresholdSent,
                isDemoData: account.isDemoData
            )
        }

        let groupSnapshots = categoryGroups.compactMap { group -> EscapeBudgetBackup.CategoryGroupSnapshot? in
            guard let id = groupIDs[group.persistentModelID] else { return nil }
            return .init(
                id: id,
                name: group.name,
                order: group.order,
                typeRawValue: group.typeRawValue,
                isDemoData: group.isDemoData
            )
        }

        let categorySnapshots = categories.compactMap { category -> EscapeBudgetBackup.CategorySnapshot? in
            guard let id = categoryIDs[category.persistentModelID] else { return nil }
            let groupID = category.group.flatMap { groupIDs[$0.persistentModelID] }
            let goalID = category.savingsGoal.flatMap { goalIDs[$0.persistentModelID] }
            return .init(
                id: id,
                name: category.name,
                assigned: category.assigned,
                activity: category.activity,
                order: category.order,
                groupID: groupID,
                savingsGoalID: goalID,
                icon: category.icon,
                memo: category.memo,
                isDemoData: category.isDemoData
            )
        }

        let tagSnapshots = tags.compactMap { tag -> EscapeBudgetBackup.TransactionTagSnapshot? in
            guard let id = tagIDs[tag.persistentModelID] else { return nil }
            return .init(id: id, name: tag.name, colorHex: tag.colorHex, order: tag.order, isDemoData: tag.isDemoData)
        }

        let goalSnapshots = goals.compactMap { goal -> EscapeBudgetBackup.SavingsGoalSnapshot? in
            guard let id = goalIDs[goal.persistentModelID] else { return nil }
            let categoryID = goal.category.flatMap { categoryIDs[$0.persistentModelID] }
            return .init(
                id: id,
                name: goal.name,
                targetAmount: goal.targetAmount,
                currentAmount: goal.currentAmount,
                targetDate: goal.targetDate,
                monthlyContribution: goal.monthlyContribution,
                colorHex: goal.colorHex,
                notes: goal.notes,
                isAchieved: goal.isAchieved,
                createdDate: goal.createdDate,
                categoryID: categoryID,
                isDemoData: goal.isDemoData
            )
        }

        let transactionSnapshots = transactions.compactMap { tx -> EscapeBudgetBackup.TransactionSnapshot? in
            guard let id = transactionIDs[tx.persistentModelID] else { return nil }
            let accountID = tx.account.flatMap { accountIDs[$0.persistentModelID] }
            let categoryID = tx.category.flatMap { categoryIDs[$0.persistentModelID] }
            let parentID = tx.parentTransaction.flatMap { transactionIDs[$0.persistentModelID] }
            let tags = (tx.tags ?? []).compactMap { tagIDs[$0.persistentModelID] }
            return .init(
                id: id,
                date: tx.date,
                payee: tx.payee,
                amount: tx.amount,
                memo: tx.memo,
                statusRawValue: tx.statusRawValue,
                kindRawValue: tx.kindRawValue,
                transferID: tx.transferID,
                transferInboxDismissed: tx.transferInboxDismissed,
                externalTransferLabel: tx.externalTransferLabel,
                accountID: accountID,
                categoryID: categoryID,
                tagIDs: tags,
                parentID: parentID,
                isDemoData: tx.isDemoData
            )
        }

        let historySnapshots = historyEntries.map { entry in
            EscapeBudgetBackup.TransactionHistoryEntrySnapshot(
                id: UUID(),
                timestamp: entry.timestamp,
                detail: entry.detail,
                transactionID: entry.transaction.flatMap { transactionIDs[$0.persistentModelID] }
            )
        }

        let purchasedItemSnapshots = purchasedItems.map { item in
            EscapeBudgetBackup.PurchasedItemSnapshot(
                id: UUID(),
                name: item.name,
                price: item.price,
                note: item.note,
                order: item.order,
                createdAt: item.createdAt,
                transactionID: item.transaction.flatMap { transactionIDs[$0.persistentModelID] },
                isDemoData: item.isDemoData
            )
        }

        let autoRuleSnapshots: [EscapeBudgetBackup.AutoRuleSnapshot] = autoRules.map { rule in
            EscapeBudgetBackup.AutoRuleSnapshot(
                id: rule.id,
                name: rule.name,
                isEnabled: rule.isEnabled,
                order: rule.order,
                createdAt: rule.createdAt,
                updatedAt: rule.updatedAt,
                matchPayeeConditionRaw: rule.matchPayeeConditionRaw,
                matchPayeeValue: rule.matchPayeeValue,
                matchPayeeCaseSensitive: rule.matchPayeeCaseSensitive,
                matchAccountID: rule.matchAccount.flatMap { accountIDs[$0.persistentModelID] },
                matchAmountConditionRaw: rule.matchAmountConditionRaw,
                matchAmountValue: rule.matchAmountValue,
                matchAmountValueMax: rule.matchAmountValueMax,
                actionRenamePayee: rule.actionRenamePayee,
                actionCategoryID: rule.actionCategory.flatMap { categoryIDs[$0.persistentModelID] },
                actionTagIDs: (rule.actionTags ?? []).compactMap { tagIDs[$0.persistentModelID] },
                actionMemo: rule.actionMemo,
                actionAppendMemo: rule.actionAppendMemo,
                actionStatusRaw: rule.actionStatusRaw,
                timesApplied: rule.timesApplied,
                lastAppliedAt: rule.lastAppliedAt
            )
        }

        let autoRuleAppSnapshots: [EscapeBudgetBackup.AutoRuleApplicationSnapshot] = autoRuleApplications.map { app in
            EscapeBudgetBackup.AutoRuleApplicationSnapshot(
                id: app.id,
                appliedAt: app.appliedAt,
                fieldChanged: app.fieldChanged,
                oldValue: app.oldValue,
                newValue: app.newValue,
                wasOverridden: app.wasOverridden,
                ruleID: app.rule?.id,
                transactionID: app.transaction.flatMap { transactionIDs[$0.persistentModelID] }
            )
        }

        let recurringSnapshots: [EscapeBudgetBackup.RecurringPurchaseSnapshot] = recurring.map { item in
            EscapeBudgetBackup.RecurringPurchaseSnapshot(
                id: UUID(),
                name: item.name,
                amount: item.amount,
                frequency: item.frequency,
                nextDate: item.nextDate,
                category: item.category,
                notes: item.notes,
                isActive: item.isActive,
                createdDate: item.createdDate,
                isDemoData: item.isDemoData
            )
        }

        let planSnapshots: [EscapeBudgetBackup.PurchasePlanSnapshot] = plans.map { item in
            EscapeBudgetBackup.PurchasePlanSnapshot(
                id: UUID(),
                itemName: item.itemName,
                expectedPrice: item.expectedPrice,
                purchaseDate: item.purchaseDate,
                url: item.url,
                category: item.category,
                priority: item.priority,
                notes: item.notes,
                imageData: item.imageData,
                isPurchased: item.isPurchased,
                actualPrice: item.actualPrice,
                actualPurchaseDate: item.actualPurchaseDate,
                createdDate: item.createdDate,
                isDemoData: item.isDemoData
            )
        }

        let widgetSnapshots: [EscapeBudgetBackup.CustomDashboardWidgetSnapshot] = widgets.map { widget in
            EscapeBudgetBackup.CustomDashboardWidgetSnapshot(
                id: widget.id,
                title: widget.title,
                order: widget.order,
                widgetType: widget.widgetType,
                chartType: widget.chartType,
                dataType: widget.dataType,
                dateRange: widget.dateRange,
                isDemoData: widget.isDemoData
            )
        }

        let notificationSnapshots: [EscapeBudgetBackup.AppNotificationSnapshot] = notifications.map { note in
            EscapeBudgetBackup.AppNotificationSnapshot(
                id: note.id,
                title: note.title,
                message: note.message,
                date: note.date,
                isRead: note.isRead,
                type: note.type,
                isDemoData: note.isDemoData
            )
        }

        let defaults = UserDefaults.standard
        let settings = EscapeBudgetBackup.Settings(
            currencyCode: defaults.string(forKey: "currencyCode"),
            userAppearance: defaults.string(forKey: "userAppearance"),
            appIconMode: defaults.string(forKey: "appIconMode"),
            appColorMode: defaults.string(forKey: "appColorMode"),
            iCloudSyncEnabled: defaults.object(forKey: "sync.icloud.enabled") as? Bool,
            showTransactionTags: defaults.object(forKey: "showTransactionTags") as? Bool,
            budgetAlerts: defaults.object(forKey: "budgetAlerts") as? Bool,
            billReminders: defaults.object(forKey: "billReminders") as? Bool,
            transfersInboxNotifications: defaults.object(forKey: "notifications.transfersInbox") as? Bool,
            importCompleteNotifications: defaults.object(forKey: "notifications.importComplete") as? Bool,
            exportStatusNotifications: defaults.object(forKey: "notifications.exportStatus") as? Bool,
            backupRestoreNotifications: defaults.object(forKey: "notifications.backupRestore") as? Bool,
            ruleAppliedNotifications: defaults.object(forKey: "notifications.ruleApplied") as? Bool,
            badgeAchievementNotifications: defaults.object(forKey: "notifications.badges") as? Bool,
            showSensitiveNotificationContent: defaults.object(forKey: "notifications.showSensitiveContent") as? Bool,
            billReminderDays: defaults.object(forKey: "billReminderDays") as? Int,
            appLanguage: defaults.string(forKey: "appLanguage"),
            weekStartDay: defaults.string(forKey: "weekStartDay"),
            relockAfterBackground: defaults.object(forKey: "security.relockAfterBackground") as? Bool,
            normalizePayeeOnImport: defaults.object(forKey: "transactions.normalizePayeeOnImport") as? Bool,
            applyAutoRulesOnImport: defaults.object(forKey: "transactions.applyAutoRulesOnImport") as? Bool,
            detectDuplicatesOnImport: defaults.object(forKey: "transactions.detectDuplicatesOnImport") as? Bool,
            suggestTransfersOnImport: defaults.object(forKey: "transactions.suggestTransfersOnImport") as? Bool,
            saveProcessingHistory: defaults.object(forKey: "transactions.saveProcessingHistory") as? Bool,
            cashflowHorizonDays: defaults.object(forKey: "cashflow.horizonDays") as? Int,
            cashflowIncludeIncome: defaults.object(forKey: "cashflow.includeIncome") as? Bool,
            cashflowMonthlyIncome: defaults.object(forKey: "cashflow.monthlyIncome") as? Double,
            cashflowIncludeChequing: defaults.object(forKey: "cashflow.includeChequing") as? Bool,
            cashflowIncludeSavings: defaults.object(forKey: "cashflow.includeSavings") as? Bool,
            cashflowIncludeOtherCash: defaults.object(forKey: "cashflow.includeOtherCash") as? Bool,
            retirement: EscapeBudgetBackup.RetirementSettings(
                isConfigured: defaults.object(forKey: "retirement.isConfigured") as? Bool,
                scenario: defaults.string(forKey: "retirement.scenario"),
                currentAge: defaults.object(forKey: "retirement.currentAge") as? Int,
                targetAge: defaults.object(forKey: "retirement.targetAge") as? Int,
                includeInvestmentAccounts: defaults.object(forKey: "retirement.includeInvestmentAccounts") as? Bool,
                includeSavingsAccounts: defaults.object(forKey: "retirement.includeSavingsAccounts") as? Bool,
                includeOtherPositiveAccounts: defaults.object(forKey: "retirement.includeOtherPositiveAccounts") as? Bool,
                useSpendingFromTransactions: defaults.object(forKey: "retirement.useSpendingFromTransactions") as? Bool,
                spendingMonthlyOverride: defaults.string(forKey: "retirement.spendingMonthlyOverride"),
                useInferredContributions: defaults.object(forKey: "retirement.useInferredContributions") as? Bool,
                monthlyContributionOverride: defaults.string(forKey: "retirement.monthlyContributionOverride"),
                externalAssets: defaults.string(forKey: "retirement.externalAssets"),
                otherIncomeMonthly: defaults.string(forKey: "retirement.otherIncomeMonthly"),
                useManualTarget: defaults.object(forKey: "retirement.useManualTarget") as? Bool,
                manualTarget: defaults.string(forKey: "retirement.manualTarget"),
                safeWithdrawalRate: defaults.object(forKey: "retirement.safeWithdrawalRate") as? Double,
                realReturn: defaults.object(forKey: "retirement.realReturn") as? Double,
                showAdvanced: defaults.object(forKey: "retirement.showAdvanced") as? Bool
            )
        )

        let app = EscapeBudgetBackup.AppInfo(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "EscapeBudget",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )

        return EscapeBudgetBackup(
            format: formatIdentifier,
            version: currentVersion,
            exportedAt: Date(),
            app: app,
            settings: settings,
            accounts: accountSnapshots,
            categoryGroups: groupSnapshots,
            categories: categorySnapshots,
            tags: tagSnapshots,
            savingsGoals: goalSnapshots,
            transactions: transactionSnapshots,
            transactionHistoryEntries: historySnapshots,
            purchasedItems: purchasedItemSnapshots,
            autoRules: autoRuleSnapshots,
            autoRuleApplications: autoRuleAppSnapshots,
            recurringPurchases: recurringSnapshots,
            purchasePlans: planSnapshots,
            customDashboardWidgets: widgetSnapshots,
            notifications: notificationSnapshots
        )
    }

    static func encode(_ backup: EscapeBudgetBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> EscapeBudgetBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EscapeBudgetBackup.self, from: data)
    }

    @MainActor
    static func restore(_ backup: EscapeBudgetBackup, modelContext: ModelContext) throws {
        guard backup.format == formatIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try deleteAllUserData(modelContext: modelContext)

        var accountsByID: [UUID: Account] = [:]
        for snap in backup.accounts {
            let type = AccountType(rawValue: snap.typeRawValue) ?? .chequing
            let account = Account(
                name: snap.name,
                type: type,
                balance: snap.balance,
                notes: snap.notes,
                createdAt: snap.createdAt ?? Date(),
                isTrackingOnly: snap.isTrackingOnly ?? false,
                lastReconciledAt: snap.lastReconciledAt,
                reconcileReminderLastThresholdSent: snap.reconcileReminderLastThresholdSent ?? 0,
                isDemoData: snap.isDemoData
            )
            modelContext.insert(account)
            accountsByID[snap.id] = account
        }

        var groupsByID: [UUID: CategoryGroup] = [:]
        for snap in backup.categoryGroups {
            let type = CategoryGroupType(rawValue: snap.typeRawValue) ?? .expense
            let group = CategoryGroup(name: snap.name, order: snap.order, type: type, isDemoData: snap.isDemoData)
            group.categories = []
            modelContext.insert(group)
            groupsByID[snap.id] = group
        }

        var categoriesByID: [UUID: Category] = [:]
        for snap in backup.categories {
            let category = Category(
                name: snap.name,
                assigned: snap.assigned,
                activity: snap.activity,
                order: snap.order,
                icon: snap.icon,
                memo: snap.memo,
                isDemoData: snap.isDemoData
            )
            if let groupID = snap.groupID, let group = groupsByID[groupID] {
                category.group = group
                if group.categories == nil { group.categories = [] }
                group.categories?.append(category)
            }
            modelContext.insert(category)
            categoriesByID[snap.id] = category
        }

        var tagsByID: [UUID: TransactionTag] = [:]
        for snap in backup.tags {
            let tag = TransactionTag(name: snap.name, colorHex: snap.colorHex, order: snap.order, isDemoData: snap.isDemoData)
            modelContext.insert(tag)
            tagsByID[snap.id] = tag
        }

        var goalsByID: [UUID: SavingsGoal] = [:]
        for snap in backup.savingsGoals {
            let goal = SavingsGoal(
                name: snap.name,
                targetAmount: snap.targetAmount,
                currentAmount: snap.currentAmount,
                targetDate: snap.targetDate,
                monthlyContribution: snap.monthlyContribution,
                colorHex: snap.colorHex,
                notes: snap.notes,
                isAchieved: snap.isAchieved,
                isDemoData: snap.isDemoData
            )
            goal.createdDate = snap.createdDate

            if let categoryID = snap.categoryID, let category = categoriesByID[categoryID] {
                goal.category = category
                category.savingsGoal = goal
            }

            modelContext.insert(goal)
            goalsByID[snap.id] = goal
        }

        // Second pass to connect category -> savingsGoal by ID if present.
        for snap in backup.categories {
            guard let goalID = snap.savingsGoalID,
                  let goal = goalsByID[goalID],
                  let category = categoriesByID[snap.id] else { continue }
            category.savingsGoal = goal
            goal.category = category
        }

        var transactionsByID: [UUID: Transaction] = [:]
        for snap in backup.transactions {
            let status = TransactionStatus(rawValue: snap.statusRawValue) ?? .uncleared
            let kind = TransactionKind(rawValue: snap.kindRawValue) ?? .standard
            let account = snap.accountID.flatMap { accountsByID[$0] }
            let category = snap.categoryID.flatMap { categoriesByID[$0] }
            let tx = Transaction(
                date: snap.date,
                payee: snap.payee,
                amount: snap.amount,
                memo: TransactionTextLimits.normalizedMemo(snap.memo),
                status: status,
                kind: kind,
                transferID: snap.transferID,
                account: account,
                category: category,
                parentTransaction: nil,
                tags: nil,
                isDemoData: snap.isDemoData
            )
            tx.transferInboxDismissed = snap.transferInboxDismissed
            tx.externalTransferLabel = snap.externalTransferLabel
            modelContext.insert(tx)
            transactionsByID[snap.id] = tx
        }

        // Connect parent/splits and tags after all transactions exist.
        for snap in backup.transactions {
            guard let tx = transactionsByID[snap.id] else { continue }
            if let parentID = snap.parentID, let parent = transactionsByID[parentID] {
                tx.parentTransaction = parent
            }
            if !snap.tagIDs.isEmpty {
                tx.tags = snap.tagIDs.compactMap { tagsByID[$0] }
            }
        }

        for snap in backup.purchasedItems {
            guard let txID = snap.transactionID, let tx = transactionsByID[txID] else { continue }
            let item = PurchasedItem(
                name: TransactionTextLimits.normalizedPurchasedItemName(snap.name),
                price: snap.price,
                note: TransactionTextLimits.normalizedPurchasedItemNote(snap.note),
                order: snap.order,
                createdAt: snap.createdAt,
                transaction: tx,
                isDemoData: snap.isDemoData
            )
            modelContext.insert(item)
        }

        // Restore history, but keep it bounded so it doesn't grow unreasonably large over time.
        let maxPerTransaction = TransactionTextLimits.maxHistoryEntriesPerTransaction
        let historyGrouped = Dictionary(grouping: backup.transactionHistoryEntries) { $0.transactionID }

        for (txID, entries) in historyGrouped {
            let sorted = entries.sorted { $0.timestamp > $1.timestamp }
            let limited = sorted.prefix(maxPerTransaction)

            for snap in limited {
                guard let txID, let tx = transactionsByID[txID] else { continue }
                let entry = TransactionHistoryEntry(
                    timestamp: snap.timestamp,
                    detail: TransactionTextLimits.normalizedHistoryDetail(snap.detail),
                    transaction: tx
                )
                modelContext.insert(entry)
            }
        }

        var rulesByID: [UUID: AutoRule] = [:]
        for snap in backup.autoRules {
            let rule = AutoRule(name: snap.name, isEnabled: snap.isEnabled, order: snap.order)
            rule.id = snap.id
            rule.createdAt = snap.createdAt
            rule.updatedAt = snap.updatedAt
            rule.matchPayeeConditionRaw = snap.matchPayeeConditionRaw
            rule.matchPayeeValue = snap.matchPayeeValue
            rule.matchPayeeCaseSensitive = snap.matchPayeeCaseSensitive
            rule.matchAccount = snap.matchAccountID.flatMap { accountsByID[$0] }
            rule.matchAmountConditionRaw = snap.matchAmountConditionRaw
            rule.matchAmountValue = snap.matchAmountValue
            rule.matchAmountValueMax = snap.matchAmountValueMax
            rule.actionRenamePayee = snap.actionRenamePayee
            rule.actionCategory = snap.actionCategoryID.flatMap { categoriesByID[$0] }
            rule.actionTags = snap.actionTagIDs.compactMap { tagsByID[$0] }
            rule.actionMemo = snap.actionMemo
            rule.actionAppendMemo = snap.actionAppendMemo
            rule.actionStatusRaw = snap.actionStatusRaw
            rule.timesApplied = snap.timesApplied
            rule.lastAppliedAt = snap.lastAppliedAt
            modelContext.insert(rule)
            rulesByID[rule.id] = rule
        }

        for snap in backup.autoRuleApplications {
            guard let ruleID = snap.ruleID,
                  let rule = rulesByID[ruleID],
                  let txID = snap.transactionID,
                  let tx = transactionsByID[txID] else { continue }
            let app = AutoRuleApplication(rule: rule, transaction: tx, fieldChanged: snap.fieldChanged, oldValue: snap.oldValue, newValue: snap.newValue)
            app.id = snap.id
            app.appliedAt = snap.appliedAt
            app.wasOverridden = snap.wasOverridden
            modelContext.insert(app)
        }

        for snap in backup.recurringPurchases {
            let item = RecurringPurchase(
                name: snap.name,
                amount: snap.amount,
                frequency: RecurrenceFrequency(rawValue: snap.frequency) ?? .monthly,
                nextDate: snap.nextDate,
                category: snap.category,
                notes: snap.notes,
                isActive: snap.isActive,
                isDemoData: snap.isDemoData
            )
            item.createdDate = snap.createdDate
            modelContext.insert(item)
        }

        for snap in backup.purchasePlans {
            let item = PurchasePlan(
                itemName: snap.itemName,
                expectedPrice: snap.expectedPrice,
                purchaseDate: snap.purchaseDate,
                url: snap.url,
                category: snap.category,
                priority: snap.priority,
                notes: snap.notes,
                imageData: snap.imageData,
                isPurchased: snap.isPurchased,
                actualPrice: snap.actualPrice,
                actualPurchaseDate: snap.actualPurchaseDate,
                isDemoData: snap.isDemoData
            )
            item.createdDate = snap.createdDate
            modelContext.insert(item)
        }

        for snap in backup.customDashboardWidgets {
            let widget = CustomDashboardWidget(
                title: snap.title,
                order: snap.order,
                widgetType: snap.widgetType,
                chartType: snap.chartType,
                dataType: snap.dataType,
                dateRange: snap.dateRange,
                isDemoData: snap.isDemoData
            )
            widget.id = snap.id
            modelContext.insert(widget)
        }

        for snap in backup.notifications {
            let note = AppNotification(title: snap.title, message: snap.message, date: snap.date, type: snap.type, isRead: snap.isRead, isDemoData: snap.isDemoData)
            note.id = snap.id
            modelContext.insert(note)
        }

        try modelContext.save()
        DataSeeder.ensureSystemGroups(context: modelContext)
        restoreDefaults(backup.settings)
    }

    @MainActor
    private static func deleteAllUserData(modelContext: ModelContext) throws {
        try modelContext.delete(model: AutoRuleApplication.self)
        try modelContext.delete(model: AutoRule.self)
        try modelContext.delete(model: TransactionHistoryEntry.self)
        try modelContext.delete(model: PurchasedItem.self)
        try modelContext.delete(model: Transaction.self)
        try modelContext.delete(model: TransactionTag.self)
        try modelContext.delete(model: SavingsGoal.self)
        try modelContext.delete(model: Category.self)
        try modelContext.delete(model: CategoryGroup.self)
        try modelContext.delete(model: Account.self)
        try modelContext.delete(model: PurchasePlan.self)
        try modelContext.delete(model: RecurringPurchase.self)
        try modelContext.delete(model: TransferPattern.self)
        try modelContext.delete(model: CategoryPattern.self)
        try modelContext.delete(model: PayeePattern.self)
        try modelContext.delete(model: RecurringPattern.self)
        try modelContext.delete(model: BudgetForecast.self)
        try modelContext.delete(model: DiagnosticEvent.self)
        try modelContext.delete(model: AppNotification.self)
        try modelContext.delete(model: CustomDashboardWidget.self)
        try modelContext.save()
    }

    private static func restoreDefaults(_ settings: EscapeBudgetBackup.Settings) {
        let defaults = UserDefaults.standard
        if let currencyCode = settings.currencyCode { defaults.set(currencyCode, forKey: "currencyCode") }
        if let userAppearance = settings.userAppearance { defaults.set(userAppearance, forKey: "userAppearance") }
        if let appIconMode = settings.appIconMode { defaults.set(appIconMode, forKey: "appIconMode") }
        if let appColorMode = settings.appColorMode { defaults.set(appColorMode, forKey: "appColorMode") }
        if let iCloudSyncEnabled = settings.iCloudSyncEnabled { defaults.set(iCloudSyncEnabled, forKey: "sync.icloud.enabled") }
        if let showTransactionTags = settings.showTransactionTags { defaults.set(showTransactionTags, forKey: "showTransactionTags") }
        if let budgetAlerts = settings.budgetAlerts { defaults.set(budgetAlerts, forKey: "budgetAlerts") }
        if let billReminders = settings.billReminders { defaults.set(billReminders, forKey: "billReminders") }
        if let v = settings.transfersInboxNotifications { defaults.set(v, forKey: "notifications.transfersInbox") }
        if let v = settings.importCompleteNotifications { defaults.set(v, forKey: "notifications.importComplete") }
        if let v = settings.exportStatusNotifications { defaults.set(v, forKey: "notifications.exportStatus") }
        if let v = settings.backupRestoreNotifications { defaults.set(v, forKey: "notifications.backupRestore") }
        if let v = settings.ruleAppliedNotifications { defaults.set(v, forKey: "notifications.ruleApplied") }
        if let v = settings.badgeAchievementNotifications { defaults.set(v, forKey: "notifications.badges") }
        if let v = settings.showSensitiveNotificationContent { defaults.set(v, forKey: "notifications.showSensitiveContent") }
        if let billReminderDays = settings.billReminderDays { defaults.set(billReminderDays, forKey: "billReminderDays") }
        if let appLanguage = settings.appLanguage { defaults.set(appLanguage, forKey: "appLanguage") }
        if let weekStartDay = settings.weekStartDay { defaults.set(weekStartDay, forKey: "weekStartDay") }
        if let relockAfterBackground = settings.relockAfterBackground { defaults.set(relockAfterBackground, forKey: "security.relockAfterBackground") }
        if let v = settings.normalizePayeeOnImport { defaults.set(v, forKey: "transactions.normalizePayeeOnImport") }
        if let v = settings.applyAutoRulesOnImport { defaults.set(v, forKey: "transactions.applyAutoRulesOnImport") }
        if let v = settings.detectDuplicatesOnImport { defaults.set(v, forKey: "transactions.detectDuplicatesOnImport") }
        if let v = settings.suggestTransfersOnImport { defaults.set(v, forKey: "transactions.suggestTransfersOnImport") }
        if let v = settings.saveProcessingHistory { defaults.set(v, forKey: "transactions.saveProcessingHistory") }
        if let v = settings.cashflowHorizonDays { defaults.set(v, forKey: "cashflow.horizonDays") }
        if let v = settings.cashflowIncludeIncome { defaults.set(v, forKey: "cashflow.includeIncome") }
        if let v = settings.cashflowMonthlyIncome { defaults.set(v, forKey: "cashflow.monthlyIncome") }
        if let v = settings.cashflowIncludeChequing { defaults.set(v, forKey: "cashflow.includeChequing") }
        if let v = settings.cashflowIncludeSavings { defaults.set(v, forKey: "cashflow.includeSavings") }
        if let v = settings.cashflowIncludeOtherCash { defaults.set(v, forKey: "cashflow.includeOtherCash") }

        if let retirement = settings.retirement {
            if let v = retirement.isConfigured { defaults.set(v, forKey: "retirement.isConfigured") }
            if let v = retirement.scenario { defaults.set(v, forKey: "retirement.scenario") }
            if let currentAge = retirement.currentAge { defaults.set(currentAge, forKey: "retirement.currentAge") }
            if let targetAge = retirement.targetAge { defaults.set(targetAge, forKey: "retirement.targetAge") }
            if let v = retirement.includeInvestmentAccounts { defaults.set(v, forKey: "retirement.includeInvestmentAccounts") }
            if let v = retirement.includeSavingsAccounts { defaults.set(v, forKey: "retirement.includeSavingsAccounts") }
            if let v = retirement.includeOtherPositiveAccounts { defaults.set(v, forKey: "retirement.includeOtherPositiveAccounts") }
            if let v = retirement.useSpendingFromTransactions { defaults.set(v, forKey: "retirement.useSpendingFromTransactions") }
            if let v = retirement.spendingMonthlyOverride { defaults.set(v, forKey: "retirement.spendingMonthlyOverride") }
            if let v = retirement.useInferredContributions { defaults.set(v, forKey: "retirement.useInferredContributions") }
            if let v = retirement.monthlyContributionOverride { defaults.set(v, forKey: "retirement.monthlyContributionOverride") }
            if let v = retirement.externalAssets { defaults.set(v, forKey: "retirement.externalAssets") }
            if let v = retirement.otherIncomeMonthly { defaults.set(v, forKey: "retirement.otherIncomeMonthly") }
            if let v = retirement.useManualTarget { defaults.set(v, forKey: "retirement.useManualTarget") }
            if let v = retirement.manualTarget { defaults.set(v, forKey: "retirement.manualTarget") }
            if let v = retirement.safeWithdrawalRate { defaults.set(v, forKey: "retirement.safeWithdrawalRate") }
            if let v = retirement.realReturn { defaults.set(v, forKey: "retirement.realReturn") }
            if let v = retirement.showAdvanced { defaults.set(v, forKey: "retirement.showAdvanced") }
        }
    }
}
