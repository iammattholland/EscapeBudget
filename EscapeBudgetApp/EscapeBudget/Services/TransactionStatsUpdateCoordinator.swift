import Foundation
import SwiftData

enum TransactionStatsUpdateCoordinator {
    static let didMarkDirtyNotification = Notification.Name("EscapeBudget.TransactionStatsDidMarkDirty")

    private static let dirtyAccountMonthsKey = "EscapeBudget.stats.dirty.accountMonths"
    private static let dirtyCashflowMonthsKey = "EscapeBudget.stats.dirty.cashflowMonths"
    private static let fullRebuildNeededKey = "EscapeBudget.stats.dirty.fullRebuildNeeded"
    private static let deferUpdatesKey = "EscapeBudget.stats.deferUpdates"

    struct DirtyState {
        var accountMonthKeys: Set<String>
        var cashflowMonthKeys: Set<String>
        var needsFullRebuild: Bool
    }

    static func markDirty(transaction: Transaction) {
        guard let monthKey = monthKey(for: transaction.date) else { return }
        markCashflowMonthKey(monthKey)

        if let accountID = transaction.account?.persistentModelID {
            markAccountMonthKey(accountMonthKey(monthKey: monthKey, accountID: accountID))
        }

        if !isDeferringUpdates {
            notify()
        }
    }

    static func markDirty(transactionSnapshot: TransactionSnapshot) {
        guard let monthKey = monthKey(for: transactionSnapshot.date) else { return }
        markCashflowMonthKey(monthKey)
        if let accountID = transactionSnapshot.accountPersistentID {
            markAccountMonthKey(accountMonthKey(monthKey: monthKey, accountID: accountID))
        }

        if !isDeferringUpdates {
            notify()
        }
    }

    static func markDirty(monthStart: Date) {
        guard let monthKey = monthKey(for: monthStart) else { return }
        markCashflowMonthKey(monthKey)

        if !isDeferringUpdates {
            notify()
        }
    }

    static func markNeedsFullRebuild() {
        UserDefaults.standard.set(true, forKey: fullRebuildNeededKey)
        if !isDeferringUpdates {
            notify()
        }
    }

    static var isDeferringUpdates: Bool {
        UserDefaults.standard.bool(forKey: deferUpdatesKey)
    }

    static func beginDeferringUpdates() {
        UserDefaults.standard.set(true, forKey: deferUpdatesKey)
    }

    static func endDeferringUpdates() {
        UserDefaults.standard.set(false, forKey: deferUpdatesKey)
    }

    static func notify() {
        NotificationCenter.default.post(name: didMarkDirtyNotification, object: nil)
    }

    static func consumeDirtyState() -> DirtyState {
        let defaults = UserDefaults.standard

        let account = Set(defaults.array(forKey: dirtyAccountMonthsKey) as? [String] ?? [])
        let cashflow = Set(defaults.array(forKey: dirtyCashflowMonthsKey) as? [String] ?? [])
        let full = defaults.bool(forKey: fullRebuildNeededKey)

        defaults.removeObject(forKey: dirtyAccountMonthsKey)
        defaults.removeObject(forKey: dirtyCashflowMonthsKey)
        defaults.removeObject(forKey: fullRebuildNeededKey)

        return DirtyState(accountMonthKeys: account, cashflowMonthKeys: cashflow, needsFullRebuild: full)
    }

    // MARK: - Key encoding

    static func parseMonthKey(_ key: String) -> Date? {
        isoMonthStartFormatter.date(from: key)
    }

    static func parseAccountMonthKey(_ key: String) -> (monthStart: Date, accountID: PersistentIdentifier)? {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let monthString = String(parts[0])
        let idString = String(parts[1])
        guard let monthStart = parseMonthKey(monthString) else { return nil }
        guard let accountID = decodePersistentIdentifier(idString) else { return nil }
        return (monthStart, accountID)
    }

    private static func monthKey(for date: Date) -> String? {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        guard let monthStart else { return nil }
        return isoMonthStartFormatter.string(from: monthStart)
    }

    private static func accountMonthKey(monthKey: String, accountID: PersistentIdentifier) -> String {
        guard let encoded = encodePersistentIdentifier(accountID) else {
            return "\(monthKey)|"
        }
        return "\(monthKey)|\(encoded)"
    }

    private static func markAccountMonthKey(_ key: String) {
        let defaults = UserDefaults.standard
        var current = Set(defaults.array(forKey: dirtyAccountMonthsKey) as? [String] ?? [])
        current.insert(key)
        defaults.set(Array(current), forKey: dirtyAccountMonthsKey)
    }

    private static func markCashflowMonthKey(_ key: String) {
        let defaults = UserDefaults.standard
        var current = Set(defaults.array(forKey: dirtyCashflowMonthsKey) as? [String] ?? [])
        current.insert(key)
        defaults.set(Array(current), forKey: dirtyCashflowMonthsKey)
    }

    private static let isoMonthStartFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func encodePersistentIdentifier(_ id: PersistentIdentifier) -> String? {
        do {
            let data = try JSONEncoder().encode(id)
            return data.base64EncodedString()
        } catch {
            return nil
        }
    }

    private static func decodePersistentIdentifier(_ encoded: String) -> PersistentIdentifier? {
        guard !encoded.isEmpty else { return nil }
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}
