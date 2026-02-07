import Foundation
import SwiftUI

// MARK: - AppSettings

/// Centralized, @Observable settings service that replaces scattered @AppStorage declarations.
///
/// **Why this exists:**
/// The app previously used ~160 individual @AppStorage declarations spread across 40+ view files,
/// with 57 unique UserDefaults keys. This caused:
/// - Stringly-typed keys duplicated everywhere (typo risk)
/// - No single source of truth for default values
/// - Impossible to test views with mock settings
/// - Multiple independent UserDefaults reads per view init
///
/// **How to use:**
/// 1. Access via `@Environment(\.appSettings)` in any view.
/// 2. Read/write properties directly — they auto-persist to UserDefaults.
/// 3. Views automatically re-render when properties change (thanks to @Observable).
/// 4. For testing/previews, inject a fresh `AppSettings(defaults: .init(suiteName: "test")!)`.
@MainActor @Observable
final class AppSettings {
    // MARK: - Storage

    /// The backing UserDefaults store. Defaults to `.standard`, but injectable for tests.
    private let defaults: UserDefaults

    // ══════════════════════════════════════════════
    // MARK: - General / App State
    // ══════════════════════════════════════════════

    var isDemoMode: Bool {
        didSet { defaults.set(isDemoMode, forKey: Keys.isDemoMode) }
    }

    var shouldShowWelcome: Bool {
        didSet { defaults.set(shouldShowWelcome, forKey: Keys.shouldShowWelcome) }
    }

    var currencyCode: String {
        didSet { defaults.set(currencyCode, forKey: Keys.currencyCode) }
    }

    var appLanguage: String {
        didSet { defaults.set(appLanguage, forKey: Keys.appLanguage) }
    }

    var weekStartDay: String {
        didSet { defaults.set(weekStartDay, forKey: Keys.weekStartDay) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Appearance
    // ══════════════════════════════════════════════

    var userAppearance: String {
        didSet { defaults.set(userAppearance, forKey: Keys.userAppearance) }
    }

    var appIconModeRawValue: String {
        didSet { defaults.set(appIconModeRawValue, forKey: Keys.appIconMode) }
    }

    var appColorModeRawValue: String {
        didSet { defaults.set(appColorModeRawValue, forKey: Keys.appColorMode) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Notifications
    // ══════════════════════════════════════════════

    var hasNotifications: Bool {
        didSet { defaults.set(hasNotifications, forKey: Keys.hasNotifications) }
    }

    var budgetAlerts: Bool {
        didSet { defaults.set(budgetAlerts, forKey: Keys.budgetAlerts) }
    }

    var billReminders: Bool {
        didSet { defaults.set(billReminders, forKey: Keys.billReminders) }
    }

    var transfersInboxNotifications: Bool {
        didSet { defaults.set(transfersInboxNotifications, forKey: Keys.notificationsTransfersInbox) }
    }

    var importCompleteNotifications: Bool {
        didSet { defaults.set(importCompleteNotifications, forKey: Keys.notificationsImportComplete) }
    }

    var exportStatusNotifications: Bool {
        didSet { defaults.set(exportStatusNotifications, forKey: Keys.notificationsExportStatus) }
    }

    var backupRestoreNotifications: Bool {
        didSet { defaults.set(backupRestoreNotifications, forKey: Keys.notificationsBackupRestore) }
    }

    var ruleAppliedNotifications: Bool {
        didSet { defaults.set(ruleAppliedNotifications, forKey: Keys.notificationsRuleApplied) }
    }

    var badgeAchievementNotifications: Bool {
        didSet { defaults.set(badgeAchievementNotifications, forKey: Keys.notificationsBadges) }
    }

    var showSensitiveNotificationContent: Bool {
        didSet { defaults.set(showSensitiveNotificationContent, forKey: Keys.notificationsShowSensitiveContent) }
    }

    var notificationsHubSelectedTab: String {
        didSet { defaults.set(notificationsHubSelectedTab, forKey: Keys.notificationsHubSelectedTab) }
    }

    // ══════════════════════════════════════════════
    // MARK: - iCloud Sync
    // ══════════════════════════════════════════════

    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.syncICloudEnabled) }
    }

    var lastSyncAttempt: Double {
        didSet { defaults.set(lastSyncAttempt, forKey: Keys.syncICloudLastAttempt) }
    }

    var lastSyncSuccess: Double {
        didSet { defaults.set(lastSyncSuccess, forKey: Keys.syncICloudLastSuccess) }
    }

    var lastSyncError: String {
        didSet { defaults.set(lastSyncError, forKey: Keys.syncICloudLastError) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Export
    // ══════════════════════════════════════════════

    var isEncryptedExport: Bool {
        didSet { defaults.set(isEncryptedExport, forKey: Keys.exportEncrypted) }
    }

    var exportPlaintextConfirmed: Bool {
        didSet { defaults.set(exportPlaintextConfirmed, forKey: Keys.exportPlaintextConfirmed) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Import
    // ══════════════════════════════════════════════

    var normalizePayeeOnImport: Bool {
        didSet { defaults.set(normalizePayeeOnImport, forKey: Keys.transactionsNormalizePayeeOnImport) }
    }

    var applyAutoRulesOnImport: Bool {
        didSet { defaults.set(applyAutoRulesOnImport, forKey: Keys.transactionsApplyAutoRulesOnImport) }
    }

    var detectDuplicatesOnImport: Bool {
        didSet { defaults.set(detectDuplicatesOnImport, forKey: Keys.transactionsDetectDuplicatesOnImport) }
    }

    var suggestTransfersOnImport: Bool {
        didSet { defaults.set(suggestTransfersOnImport, forKey: Keys.transactionsSuggestTransfersOnImport) }
    }

    var saveProcessingHistory: Bool {
        didSet { defaults.set(saveProcessingHistory, forKey: Keys.transactionsSaveProcessingHistory) }
    }

    var lastUsedImportSource: String? {
        didSet { defaults.set(lastUsedImportSource, forKey: Keys.importLastUsedSource) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Transactions
    // ══════════════════════════════════════════════

    var showTransactionTags: Bool {
        didSet { defaults.set(showTransactionTags, forKey: Keys.showTransactionTags) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Cash Flow Forecast
    // ══════════════════════════════════════════════

    var cashflowHorizonDays: Int {
        didSet { defaults.set(cashflowHorizonDays, forKey: Keys.cashflowHorizonDays) }
    }

    var cashflowIncludeIncome: Bool {
        didSet { defaults.set(cashflowIncludeIncome, forKey: Keys.cashflowIncludeIncome) }
    }

    var cashflowMonthlyIncome: Double {
        didSet { defaults.set(cashflowMonthlyIncome, forKey: Keys.cashflowMonthlyIncome) }
    }

    var cashflowIncludeChequing: Bool {
        didSet { defaults.set(cashflowIncludeChequing, forKey: Keys.cashflowIncludeChequing) }
    }

    var cashflowIncludeSavings: Bool {
        didSet { defaults.set(cashflowIncludeSavings, forKey: Keys.cashflowIncludeSavings) }
    }

    var cashflowIncludeOtherCash: Bool {
        didSet { defaults.set(cashflowIncludeOtherCash, forKey: Keys.cashflowIncludeOtherCash) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Retirement
    // ══════════════════════════════════════════════

    var retirementIsConfigured: Bool {
        didSet { defaults.set(retirementIsConfigured, forKey: Keys.retirementIsConfigured) }
    }

    var retirementScenario: String {
        didSet { defaults.set(retirementScenario, forKey: Keys.retirementScenario) }
    }

    var retirementCurrentAge: Int {
        didSet { defaults.set(retirementCurrentAge, forKey: Keys.retirementCurrentAge) }
    }

    var retirementTargetAge: Int {
        didSet { defaults.set(retirementTargetAge, forKey: Keys.retirementTargetAge) }
    }

    var retirementIncludeInvestmentAccounts: Bool {
        didSet { defaults.set(retirementIncludeInvestmentAccounts, forKey: Keys.retirementIncludeInvestmentAccounts) }
    }

    var retirementIncludeSavingsAccounts: Bool {
        didSet { defaults.set(retirementIncludeSavingsAccounts, forKey: Keys.retirementIncludeSavingsAccounts) }
    }

    var retirementIncludeOtherPositiveAccounts: Bool {
        didSet { defaults.set(retirementIncludeOtherPositiveAccounts, forKey: Keys.retirementIncludeOtherPositiveAccounts) }
    }

    var retirementUseSpendingFromTransactions: Bool {
        didSet { defaults.set(retirementUseSpendingFromTransactions, forKey: Keys.retirementUseSpendingFromTransactions) }
    }

    var retirementSpendingMonthlyOverride: String {
        didSet { defaults.set(retirementSpendingMonthlyOverride, forKey: Keys.retirementSpendingMonthlyOverride) }
    }

    var retirementUseInferredContributions: Bool {
        didSet { defaults.set(retirementUseInferredContributions, forKey: Keys.retirementUseInferredContributions) }
    }

    var retirementMonthlyContributionOverride: String {
        didSet { defaults.set(retirementMonthlyContributionOverride, forKey: Keys.retirementMonthlyContributionOverride) }
    }

    var retirementExternalAssets: String {
        didSet { defaults.set(retirementExternalAssets, forKey: Keys.retirementExternalAssets) }
    }

    var retirementOtherIncomeMonthly: String {
        didSet { defaults.set(retirementOtherIncomeMonthly, forKey: Keys.retirementOtherIncomeMonthly) }
    }

    var retirementUseManualTarget: Bool {
        didSet { defaults.set(retirementUseManualTarget, forKey: Keys.retirementUseManualTarget) }
    }

    var retirementManualTarget: String {
        didSet { defaults.set(retirementManualTarget, forKey: Keys.retirementManualTarget) }
    }

    var retirementSafeWithdrawalRate: Double {
        didSet { defaults.set(retirementSafeWithdrawalRate, forKey: Keys.retirementSafeWithdrawalRate) }
    }

    var retirementRealReturn: Double {
        didSet { defaults.set(retirementRealReturn, forKey: Keys.retirementRealReturn) }
    }

    var retirementShowAdvanced: Bool {
        didSet { defaults.set(retirementShowAdvanced, forKey: Keys.retirementShowAdvanced) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Diagnostics
    // ══════════════════════════════════════════════

    var diagnosticsLastAuditRun: Double {
        didSet { defaults.set(diagnosticsLastAuditRun, forKey: Keys.diagnosticsAuditLastRun) }
    }

    var diagnosticsLastAuditReport: String {
        didSet { defaults.set(diagnosticsLastAuditReport, forKey: Keys.diagnosticsAuditLastReport) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Bill Reminders
    // ══════════════════════════════════════════════

    var billReminderDays: Int {
        didSet { defaults.set(billReminderDays, forKey: Keys.billReminderDays) }
    }

    // ══════════════════════════════════════════════
    // MARK: - Initialization
    // ══════════════════════════════════════════════

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // General
        self.isDemoMode = defaults.bool(forKey: Keys.isDemoMode)
        self.shouldShowWelcome = defaults.object(forKey: Keys.shouldShowWelcome) == nil ? true : defaults.bool(forKey: Keys.shouldShowWelcome)
        self.currencyCode = defaults.string(forKey: Keys.currencyCode) ?? Defaults.currencyCode
        self.appLanguage = defaults.string(forKey: Keys.appLanguage) ?? Defaults.appLanguage
        self.weekStartDay = defaults.string(forKey: Keys.weekStartDay) ?? Defaults.weekStartDay

        // Appearance
        self.userAppearance = defaults.string(forKey: Keys.userAppearance) ?? Defaults.userAppearance
        self.appIconModeRawValue = defaults.string(forKey: Keys.appIconMode) ?? AppIconMode.system.rawValue
        self.appColorModeRawValue = defaults.string(forKey: Keys.appColorMode) ?? AppColorMode.standard.rawValue

        // Notifications
        self.hasNotifications = defaults.bool(forKey: Keys.hasNotifications)
        self.budgetAlerts = defaults.object(forKey: Keys.budgetAlerts) == nil ? true : defaults.bool(forKey: Keys.budgetAlerts)
        self.billReminders = defaults.object(forKey: Keys.billReminders) == nil ? true : defaults.bool(forKey: Keys.billReminders)
        self.transfersInboxNotifications = defaults.object(forKey: Keys.notificationsTransfersInbox) == nil ? true : defaults.bool(forKey: Keys.notificationsTransfersInbox)
        self.importCompleteNotifications = defaults.object(forKey: Keys.notificationsImportComplete) == nil ? true : defaults.bool(forKey: Keys.notificationsImportComplete)
        self.exportStatusNotifications = defaults.object(forKey: Keys.notificationsExportStatus) == nil ? true : defaults.bool(forKey: Keys.notificationsExportStatus)
        self.backupRestoreNotifications = defaults.object(forKey: Keys.notificationsBackupRestore) == nil ? true : defaults.bool(forKey: Keys.notificationsBackupRestore)
        self.ruleAppliedNotifications = defaults.object(forKey: Keys.notificationsRuleApplied) == nil ? true : defaults.bool(forKey: Keys.notificationsRuleApplied)
        self.badgeAchievementNotifications = defaults.object(forKey: Keys.notificationsBadges) == nil ? true : defaults.bool(forKey: Keys.notificationsBadges)
        self.showSensitiveNotificationContent = defaults.bool(forKey: Keys.notificationsShowSensitiveContent)
        self.notificationsHubSelectedTab = defaults.string(forKey: Keys.notificationsHubSelectedTab) ?? "Notifications"

        // iCloud Sync
        self.iCloudSyncEnabled = defaults.bool(forKey: Keys.syncICloudEnabled)
        self.lastSyncAttempt = defaults.double(forKey: Keys.syncICloudLastAttempt)
        self.lastSyncSuccess = defaults.double(forKey: Keys.syncICloudLastSuccess)
        self.lastSyncError = defaults.string(forKey: Keys.syncICloudLastError) ?? ""

        // Export
        self.isEncryptedExport = defaults.object(forKey: Keys.exportEncrypted) == nil ? true : defaults.bool(forKey: Keys.exportEncrypted)
        self.exportPlaintextConfirmed = defaults.bool(forKey: Keys.exportPlaintextConfirmed)

        // Import
        self.normalizePayeeOnImport = defaults.object(forKey: Keys.transactionsNormalizePayeeOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsNormalizePayeeOnImport)
        self.applyAutoRulesOnImport = defaults.object(forKey: Keys.transactionsApplyAutoRulesOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsApplyAutoRulesOnImport)
        self.detectDuplicatesOnImport = defaults.object(forKey: Keys.transactionsDetectDuplicatesOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsDetectDuplicatesOnImport)
        self.suggestTransfersOnImport = defaults.object(forKey: Keys.transactionsSuggestTransfersOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsSuggestTransfersOnImport)
        self.saveProcessingHistory = defaults.bool(forKey: Keys.transactionsSaveProcessingHistory)
        self.lastUsedImportSource = defaults.string(forKey: Keys.importLastUsedSource)

        // Transactions
        self.showTransactionTags = defaults.bool(forKey: Keys.showTransactionTags)

        // Cash Flow
        self.cashflowHorizonDays = defaults.object(forKey: Keys.cashflowHorizonDays) == nil ? Defaults.cashflowHorizonDays : defaults.integer(forKey: Keys.cashflowHorizonDays)
        self.cashflowIncludeIncome = defaults.object(forKey: Keys.cashflowIncludeIncome) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeIncome)
        self.cashflowMonthlyIncome = defaults.double(forKey: Keys.cashflowMonthlyIncome)
        self.cashflowIncludeChequing = defaults.object(forKey: Keys.cashflowIncludeChequing) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeChequing)
        self.cashflowIncludeSavings = defaults.object(forKey: Keys.cashflowIncludeSavings) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeSavings)
        self.cashflowIncludeOtherCash = defaults.object(forKey: Keys.cashflowIncludeOtherCash) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeOtherCash)

        // Retirement
        self.retirementIsConfigured = defaults.bool(forKey: Keys.retirementIsConfigured)
        self.retirementScenario = defaults.string(forKey: Keys.retirementScenario) ?? Defaults.retirementScenario
        self.retirementCurrentAge = defaults.object(forKey: Keys.retirementCurrentAge) == nil ? Defaults.retirementCurrentAge : defaults.integer(forKey: Keys.retirementCurrentAge)
        self.retirementTargetAge = defaults.object(forKey: Keys.retirementTargetAge) == nil ? Defaults.retirementTargetAge : defaults.integer(forKey: Keys.retirementTargetAge)
        self.retirementIncludeInvestmentAccounts = defaults.object(forKey: Keys.retirementIncludeInvestmentAccounts) == nil ? true : defaults.bool(forKey: Keys.retirementIncludeInvestmentAccounts)
        self.retirementIncludeSavingsAccounts = defaults.bool(forKey: Keys.retirementIncludeSavingsAccounts)
        self.retirementIncludeOtherPositiveAccounts = defaults.bool(forKey: Keys.retirementIncludeOtherPositiveAccounts)
        self.retirementUseSpendingFromTransactions = defaults.object(forKey: Keys.retirementUseSpendingFromTransactions) == nil ? true : defaults.bool(forKey: Keys.retirementUseSpendingFromTransactions)
        self.retirementSpendingMonthlyOverride = defaults.string(forKey: Keys.retirementSpendingMonthlyOverride) ?? ""
        self.retirementUseInferredContributions = defaults.object(forKey: Keys.retirementUseInferredContributions) == nil ? true : defaults.bool(forKey: Keys.retirementUseInferredContributions)
        self.retirementMonthlyContributionOverride = defaults.string(forKey: Keys.retirementMonthlyContributionOverride) ?? ""
        self.retirementExternalAssets = defaults.string(forKey: Keys.retirementExternalAssets) ?? ""
        self.retirementOtherIncomeMonthly = defaults.string(forKey: Keys.retirementOtherIncomeMonthly) ?? ""
        self.retirementUseManualTarget = defaults.bool(forKey: Keys.retirementUseManualTarget)
        self.retirementManualTarget = defaults.string(forKey: Keys.retirementManualTarget) ?? ""
        self.retirementSafeWithdrawalRate = defaults.object(forKey: Keys.retirementSafeWithdrawalRate) == nil ? Defaults.retirementSafeWithdrawalRate : defaults.double(forKey: Keys.retirementSafeWithdrawalRate)
        self.retirementRealReturn = defaults.object(forKey: Keys.retirementRealReturn) == nil ? Defaults.retirementRealReturn : defaults.double(forKey: Keys.retirementRealReturn)
        self.retirementShowAdvanced = defaults.bool(forKey: Keys.retirementShowAdvanced)

        // Diagnostics
        self.diagnosticsLastAuditRun = defaults.double(forKey: Keys.diagnosticsAuditLastRun)
        self.diagnosticsLastAuditReport = defaults.string(forKey: Keys.diagnosticsAuditLastReport) ?? ""

        // Bill Reminders
        self.billReminderDays = defaults.object(forKey: Keys.billReminderDays) == nil ? Defaults.billReminderDays : defaults.integer(forKey: Keys.billReminderDays)
    }

    // ══════════════════════════════════════════════
    // MARK: - Reload
    // ══════════════════════════════════════════════

    /// Re-reads all values from UserDefaults. Useful after external code (e.g. DemoPreferencesManager)
    /// writes directly to UserDefaults.
    func reloadFromDefaults() {
        isDemoMode = defaults.bool(forKey: Keys.isDemoMode)
        shouldShowWelcome = defaults.object(forKey: Keys.shouldShowWelcome) == nil ? true : defaults.bool(forKey: Keys.shouldShowWelcome)
        currencyCode = defaults.string(forKey: Keys.currencyCode) ?? Defaults.currencyCode
        appLanguage = defaults.string(forKey: Keys.appLanguage) ?? Defaults.appLanguage
        weekStartDay = defaults.string(forKey: Keys.weekStartDay) ?? Defaults.weekStartDay

        userAppearance = defaults.string(forKey: Keys.userAppearance) ?? Defaults.userAppearance
        appIconModeRawValue = defaults.string(forKey: Keys.appIconMode) ?? AppIconMode.system.rawValue
        appColorModeRawValue = defaults.string(forKey: Keys.appColorMode) ?? AppColorMode.standard.rawValue

        hasNotifications = defaults.bool(forKey: Keys.hasNotifications)
        budgetAlerts = defaults.object(forKey: Keys.budgetAlerts) == nil ? true : defaults.bool(forKey: Keys.budgetAlerts)
        billReminders = defaults.object(forKey: Keys.billReminders) == nil ? true : defaults.bool(forKey: Keys.billReminders)
        transfersInboxNotifications = defaults.object(forKey: Keys.notificationsTransfersInbox) == nil ? true : defaults.bool(forKey: Keys.notificationsTransfersInbox)
        importCompleteNotifications = defaults.object(forKey: Keys.notificationsImportComplete) == nil ? true : defaults.bool(forKey: Keys.notificationsImportComplete)
        exportStatusNotifications = defaults.object(forKey: Keys.notificationsExportStatus) == nil ? true : defaults.bool(forKey: Keys.notificationsExportStatus)
        backupRestoreNotifications = defaults.object(forKey: Keys.notificationsBackupRestore) == nil ? true : defaults.bool(forKey: Keys.notificationsBackupRestore)
        ruleAppliedNotifications = defaults.object(forKey: Keys.notificationsRuleApplied) == nil ? true : defaults.bool(forKey: Keys.notificationsRuleApplied)
        badgeAchievementNotifications = defaults.object(forKey: Keys.notificationsBadges) == nil ? true : defaults.bool(forKey: Keys.notificationsBadges)
        showSensitiveNotificationContent = defaults.bool(forKey: Keys.notificationsShowSensitiveContent)
        notificationsHubSelectedTab = defaults.string(forKey: Keys.notificationsHubSelectedTab) ?? "Notifications"

        iCloudSyncEnabled = defaults.bool(forKey: Keys.syncICloudEnabled)
        lastSyncAttempt = defaults.double(forKey: Keys.syncICloudLastAttempt)
        lastSyncSuccess = defaults.double(forKey: Keys.syncICloudLastSuccess)
        lastSyncError = defaults.string(forKey: Keys.syncICloudLastError) ?? ""

        isEncryptedExport = defaults.object(forKey: Keys.exportEncrypted) == nil ? true : defaults.bool(forKey: Keys.exportEncrypted)
        exportPlaintextConfirmed = defaults.bool(forKey: Keys.exportPlaintextConfirmed)

        normalizePayeeOnImport = defaults.object(forKey: Keys.transactionsNormalizePayeeOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsNormalizePayeeOnImport)
        applyAutoRulesOnImport = defaults.object(forKey: Keys.transactionsApplyAutoRulesOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsApplyAutoRulesOnImport)
        detectDuplicatesOnImport = defaults.object(forKey: Keys.transactionsDetectDuplicatesOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsDetectDuplicatesOnImport)
        suggestTransfersOnImport = defaults.object(forKey: Keys.transactionsSuggestTransfersOnImport) == nil ? true : defaults.bool(forKey: Keys.transactionsSuggestTransfersOnImport)
        saveProcessingHistory = defaults.bool(forKey: Keys.transactionsSaveProcessingHistory)
        lastUsedImportSource = defaults.string(forKey: Keys.importLastUsedSource)

        showTransactionTags = defaults.bool(forKey: Keys.showTransactionTags)

        cashflowHorizonDays = defaults.object(forKey: Keys.cashflowHorizonDays) == nil ? Defaults.cashflowHorizonDays : defaults.integer(forKey: Keys.cashflowHorizonDays)
        cashflowIncludeIncome = defaults.object(forKey: Keys.cashflowIncludeIncome) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeIncome)
        cashflowMonthlyIncome = defaults.double(forKey: Keys.cashflowMonthlyIncome)
        cashflowIncludeChequing = defaults.object(forKey: Keys.cashflowIncludeChequing) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeChequing)
        cashflowIncludeSavings = defaults.object(forKey: Keys.cashflowIncludeSavings) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeSavings)
        cashflowIncludeOtherCash = defaults.object(forKey: Keys.cashflowIncludeOtherCash) == nil ? true : defaults.bool(forKey: Keys.cashflowIncludeOtherCash)

        retirementIsConfigured = defaults.bool(forKey: Keys.retirementIsConfigured)
        retirementScenario = defaults.string(forKey: Keys.retirementScenario) ?? Defaults.retirementScenario
        retirementCurrentAge = defaults.object(forKey: Keys.retirementCurrentAge) == nil ? Defaults.retirementCurrentAge : defaults.integer(forKey: Keys.retirementCurrentAge)
        retirementTargetAge = defaults.object(forKey: Keys.retirementTargetAge) == nil ? Defaults.retirementTargetAge : defaults.integer(forKey: Keys.retirementTargetAge)
        retirementIncludeInvestmentAccounts = defaults.object(forKey: Keys.retirementIncludeInvestmentAccounts) == nil ? true : defaults.bool(forKey: Keys.retirementIncludeInvestmentAccounts)
        retirementIncludeSavingsAccounts = defaults.bool(forKey: Keys.retirementIncludeSavingsAccounts)
        retirementIncludeOtherPositiveAccounts = defaults.bool(forKey: Keys.retirementIncludeOtherPositiveAccounts)
        retirementUseSpendingFromTransactions = defaults.object(forKey: Keys.retirementUseSpendingFromTransactions) == nil ? true : defaults.bool(forKey: Keys.retirementUseSpendingFromTransactions)
        retirementSpendingMonthlyOverride = defaults.string(forKey: Keys.retirementSpendingMonthlyOverride) ?? ""
        retirementUseInferredContributions = defaults.object(forKey: Keys.retirementUseInferredContributions) == nil ? true : defaults.bool(forKey: Keys.retirementUseInferredContributions)
        retirementMonthlyContributionOverride = defaults.string(forKey: Keys.retirementMonthlyContributionOverride) ?? ""
        retirementExternalAssets = defaults.string(forKey: Keys.retirementExternalAssets) ?? ""
        retirementOtherIncomeMonthly = defaults.string(forKey: Keys.retirementOtherIncomeMonthly) ?? ""
        retirementUseManualTarget = defaults.bool(forKey: Keys.retirementUseManualTarget)
        retirementManualTarget = defaults.string(forKey: Keys.retirementManualTarget) ?? ""
        retirementSafeWithdrawalRate = defaults.object(forKey: Keys.retirementSafeWithdrawalRate) == nil ? Defaults.retirementSafeWithdrawalRate : defaults.double(forKey: Keys.retirementSafeWithdrawalRate)
        retirementRealReturn = defaults.object(forKey: Keys.retirementRealReturn) == nil ? Defaults.retirementRealReturn : defaults.double(forKey: Keys.retirementRealReturn)
        retirementShowAdvanced = defaults.bool(forKey: Keys.retirementShowAdvanced)

        diagnosticsLastAuditRun = defaults.double(forKey: Keys.diagnosticsAuditLastRun)
        diagnosticsLastAuditReport = defaults.string(forKey: Keys.diagnosticsAuditLastReport) ?? ""

        billReminderDays = defaults.object(forKey: Keys.billReminderDays) == nil ? Defaults.billReminderDays : defaults.integer(forKey: Keys.billReminderDays)
    }
}

// MARK: - UserDefaults Keys

extension AppSettings {
    /// All UserDefaults keys in one place — no more stringly-typed duplication.
    enum Keys {
        // General
        static let isDemoMode = "isDemoMode"
        static let shouldShowWelcome = "shouldShowWelcome"
        static let currencyCode = "currencyCode"
        static let appLanguage = "appLanguage"
        static let weekStartDay = "weekStartDay"

        // Appearance
        static let userAppearance = "userAppearance"
        static let appIconMode = "appIconMode"
        static let appColorMode = "appColorMode"

        // Notifications
        static let hasNotifications = "hasNotifications"
        static let budgetAlerts = "budgetAlerts"
        static let billReminders = "billReminders"
        static let notificationsTransfersInbox = "notifications.transfersInbox"
        static let notificationsImportComplete = "notifications.importComplete"
        static let notificationsExportStatus = "notifications.exportStatus"
        static let notificationsBackupRestore = "notifications.backupRestore"
        static let notificationsRuleApplied = "notifications.ruleApplied"
        static let notificationsBadges = "notifications.badges"
        static let notificationsShowSensitiveContent = "notifications.showSensitiveContent"
        static let notificationsHubSelectedTab = "notificationsHub.selectedTab"

        // iCloud Sync
        static let syncICloudEnabled = "sync.icloud.enabled"
        static let syncICloudLastAttempt = "sync.icloud.lastAttempt"
        static let syncICloudLastSuccess = "sync.icloud.lastSuccess"
        static let syncICloudLastError = "sync.icloud.lastError"

        // Export
        static let exportEncrypted = "export.encrypted"
        static let exportPlaintextConfirmed = "export.plaintextConfirmed"

        // Import / Transactions
        static let transactionsNormalizePayeeOnImport = "transactions.normalizePayeeOnImport"
        static let transactionsApplyAutoRulesOnImport = "transactions.applyAutoRulesOnImport"
        static let transactionsDetectDuplicatesOnImport = "transactions.detectDuplicatesOnImport"
        static let transactionsSuggestTransfersOnImport = "transactions.suggestTransfersOnImport"
        static let transactionsSaveProcessingHistory = "transactions.saveProcessingHistory"
        static let importLastUsedSource = "import.lastUsedSource"

        // Transactions UI
        static let showTransactionTags = "showTransactionTags"

        // Cash Flow
        static let cashflowHorizonDays = "cashflow.horizonDays"
        static let cashflowIncludeIncome = "cashflow.includeIncome"
        static let cashflowMonthlyIncome = "cashflow.monthlyIncome"
        static let cashflowIncludeChequing = "cashflow.includeChequing"
        static let cashflowIncludeSavings = "cashflow.includeSavings"
        static let cashflowIncludeOtherCash = "cashflow.includeOtherCash"

        // Retirement
        static let retirementIsConfigured = "retirement.isConfigured"
        static let retirementScenario = "retirement.scenario"
        static let retirementCurrentAge = "retirement.currentAge"
        static let retirementTargetAge = "retirement.targetAge"
        static let retirementIncludeInvestmentAccounts = "retirement.includeInvestmentAccounts"
        static let retirementIncludeSavingsAccounts = "retirement.includeSavingsAccounts"
        static let retirementIncludeOtherPositiveAccounts = "retirement.includeOtherPositiveAccounts"
        static let retirementUseSpendingFromTransactions = "retirement.useSpendingFromTransactions"
        static let retirementSpendingMonthlyOverride = "retirement.spendingMonthlyOverride"
        static let retirementUseInferredContributions = "retirement.useInferredContributions"
        static let retirementMonthlyContributionOverride = "retirement.monthlyContributionOverride"
        static let retirementExternalAssets = "retirement.externalAssets"
        static let retirementOtherIncomeMonthly = "retirement.otherIncomeMonthly"
        static let retirementUseManualTarget = "retirement.useManualTarget"
        static let retirementManualTarget = "retirement.manualTarget"
        static let retirementSafeWithdrawalRate = "retirement.safeWithdrawalRate"
        static let retirementRealReturn = "retirement.realReturn"
        static let retirementShowAdvanced = "retirement.showAdvanced"

        // Diagnostics
        static let diagnosticsAuditLastRun = "diagnostics.audit.lastRun"
        static let diagnosticsAuditLastReport = "diagnostics.audit.lastReport"

        // Bill Reminders
        static let billReminderDays = "billReminderDays"
    }
}

// MARK: - Default Values

extension AppSettings {
    /// Canonical default values. These match the previous @AppStorage defaults exactly.
    enum Defaults {
        static let currencyCode = "USD"
        static let appLanguage = "English"
        static let weekStartDay = "Sunday"
        static let userAppearance = "System"

        static let cashflowHorizonDays = 90

        static let retirementScenario = "Your Plan"
        static let retirementCurrentAge = 30
        static let retirementTargetAge = 65
        static let retirementSafeWithdrawalRate = 0.04
        static let retirementRealReturn = 0.05

        static let billReminderDays = 1
    }
}

// MARK: - SwiftUI Environment Integration

private struct AppSettingsKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppSettings()
}

extension EnvironmentValues {
    var appSettings: AppSettings {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }
}
