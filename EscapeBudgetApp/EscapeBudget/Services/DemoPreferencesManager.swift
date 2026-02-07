import Foundation

enum DemoPreferencesManager {
    private static let snapshotKey = "demo.preferencesSnapshot.v1"

    static func enterDemoMode(defaults: UserDefaults = .standard) {
        saveSnapshotIfNeeded(defaults: defaults)
        applyDemoDefaults(defaults: defaults)
    }

    static func exitDemoMode(defaults: UserDefaults = .standard) {
        restoreSnapshot(defaults: defaults)
    }

    private static func saveSnapshotIfNeeded(defaults: UserDefaults) {
        guard defaults.data(forKey: snapshotKey) == nil else { return }

        var snapshot: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            if key.hasPrefix("retirement.") || key.hasPrefix("cashflow.") {
                snapshot[key] = value
            }
        }

        guard PropertyListSerialization.propertyList(snapshot, isValidFor: .binary) else { return }
        let data = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        if let data {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    private static func restoreSnapshot(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: snapshotKey) else { return }
        defaults.removeObject(forKey: snapshotKey)

        // Clear any demo-modified keys first.
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("retirement.") || key.hasPrefix("cashflow.") {
                defaults.removeObject(forKey: key)
            }
        }

        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let snapshot = plist as? [String: Any] ?? [:]
        for (key, value) in snapshot {
            defaults.set(value, forKey: key)
        }
    }

    private static func applyDemoDefaults(defaults: UserDefaults) {
        typealias K = AppSettings.Keys

        // Cash Flow Forecast defaults (will still infer monthly income from demo transactions if 0).
        defaults.set(90, forKey: K.cashflowHorizonDays)
        defaults.set(true, forKey: K.cashflowIncludeIncome)
        defaults.set(0.0, forKey: K.cashflowMonthlyIncome)
        defaults.set(true, forKey: K.cashflowIncludeChequing)
        defaults.set(true, forKey: K.cashflowIncludeSavings)
        defaults.set(true, forKey: K.cashflowIncludeOtherCash)

        // Retirement defaults (so demo shows meaningful projections immediately).
        defaults.set(true, forKey: K.retirementIsConfigured)
        defaults.set(RetirementScenarioDemo.base.rawValue, forKey: K.retirementScenario)
        defaults.set(32, forKey: K.retirementCurrentAge)
        defaults.set(65, forKey: K.retirementTargetAge)
        defaults.set(false, forKey: K.retirementIncludeInvestmentAccounts)
        defaults.set(true, forKey: K.retirementIncludeSavingsAccounts)
        defaults.set(false, forKey: K.retirementIncludeOtherPositiveAccounts)
        defaults.set(true, forKey: K.retirementUseSpendingFromTransactions)
        defaults.set("", forKey: K.retirementSpendingMonthlyOverride)
        defaults.set(true, forKey: K.retirementUseInferredContributions)
        defaults.set("", forKey: K.retirementMonthlyContributionOverride)
        defaults.set("25000", forKey: K.retirementExternalAssets)
        defaults.set("0", forKey: K.retirementOtherIncomeMonthly)
        defaults.set(false, forKey: K.retirementUseManualTarget)
        defaults.set("", forKey: K.retirementManualTarget)
        defaults.set(0.04, forKey: K.retirementSafeWithdrawalRate)
        defaults.set(0.05, forKey: K.retirementRealReturn)
        defaults.set(false, forKey: K.retirementShowAdvanced)
    }

    private enum RetirementScenarioDemo: String {
        case base = "Base"
    }
}

