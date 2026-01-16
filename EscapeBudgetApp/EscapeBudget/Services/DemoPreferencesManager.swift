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
        // Cash Flow Forecast defaults (will still infer monthly income from demo transactions if 0).
        defaults.set(90, forKey: "cashflow.horizonDays")
        defaults.set(true, forKey: "cashflow.includeIncome")
        defaults.set(0.0, forKey: "cashflow.monthlyIncome")
        defaults.set(true, forKey: "cashflow.includeChequing")
        defaults.set(true, forKey: "cashflow.includeSavings")
        defaults.set(true, forKey: "cashflow.includeOtherCash")

        // Retirement defaults (so demo shows meaningful projections immediately).
        defaults.set(true, forKey: "retirement.isConfigured")
        defaults.set(RetirementScenarioDemo.base.rawValue, forKey: "retirement.scenario")
        defaults.set(32, forKey: "retirement.currentAge")
        defaults.set(65, forKey: "retirement.targetAge")
        defaults.set(false, forKey: "retirement.includeInvestmentAccounts")
        defaults.set(true, forKey: "retirement.includeSavingsAccounts")
        defaults.set(false, forKey: "retirement.includeOtherPositiveAccounts")
        defaults.set(true, forKey: "retirement.useSpendingFromTransactions")
        defaults.set("", forKey: "retirement.spendingMonthlyOverride")
        defaults.set(true, forKey: "retirement.useInferredContributions")
        defaults.set("", forKey: "retirement.monthlyContributionOverride")
        defaults.set("25000", forKey: "retirement.externalAssets")
        defaults.set("0", forKey: "retirement.otherIncomeMonthly")
        defaults.set(false, forKey: "retirement.useManualTarget")
        defaults.set("", forKey: "retirement.manualTarget")
        defaults.set(0.04, forKey: "retirement.safeWithdrawalRate")
        defaults.set(0.05, forKey: "retirement.realReturn")
        defaults.set(false, forKey: "retirement.showAdvanced")
    }

    private enum RetirementScenarioDemo: String {
        case base = "Base"
    }
}

