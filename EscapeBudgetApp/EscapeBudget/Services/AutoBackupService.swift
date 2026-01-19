import Foundation
import SwiftData
import os

@MainActor
enum AutoBackupService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mattholland.EscapeBudget", category: "AutoBackupService")

    enum AutoBackupError: LocalizedError {
        case destinationNotSet
        case destinationUnavailable
        case invalidDestination
        case encryptionPasswordMissing

        var errorDescription: String? {
            switch self {
            case .destinationNotSet:
                return "Choose a folder for auto-backups first."
            case .destinationUnavailable:
                return "The backup folder is unavailable. Please choose it again."
            case .invalidDestination:
                return "That backup destination can’t be used."
            case .encryptionPasswordMissing:
                return "Enter a backup password to enable encrypted auto-backups."
            }
        }
    }

    private static let defaults = UserDefaults.standard
    private static let enabledKey = "backup.auto.enabled"
    private static let encryptKey = "backup.auto.encrypt"
    private static let keepCountKey = "backup.auto.keepCount"
    private static let lastRunKey = "backup.auto.lastRun"
    private static let destinationBookmarkKey = "backup.auto.destinationBookmark"

    private static let primaryFilePrefix = "EscapeBudget_AutoBackup_"
    private static let legacyFilePrefix = "EscapeBudget_AutoBackup_"
    private static let filePrefixes = [primaryFilePrefix, legacyFilePrefix]

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var isEncrypted: Bool {
        get { defaults.object(forKey: encryptKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: encryptKey) }
    }

    static var keepCount: Int {
        get {
            let value = defaults.object(forKey: keepCountKey) as? Int ?? 12
            return max(3, min(52, value))
        }
        set {
            defaults.set(max(3, min(52, newValue)), forKey: keepCountKey)
        }
    }

    static func destinationDisplayName() -> String? {
        guard let url = try? resolveDestinationURL() else { return nil }
        return url.lastPathComponent
    }

    static func setDestination(url: URL) throws {
        guard url.hasDirectoryPath else { throw AutoBackupError.invalidDestination }
        let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: destinationBookmarkKey)
    }

    static func clearDestination() {
        defaults.removeObject(forKey: destinationBookmarkKey)
    }

    static func setEncryptionPassword(_ password: String?) {
        if let password, !password.isEmpty {
            _ = KeychainService.shared.setString(password, forKey: .autoBackupPassword)
        } else {
            KeychainService.shared.remove(forKey: .autoBackupPassword)
        }
    }

    static func getEncryptionPassword() -> String? {
        KeychainService.shared.getString(forKey: .autoBackupPassword)
    }

    static func maybeRunWeekly(modelContext: ModelContext, now: Date = Date()) async {
        let interval = PerformanceSignposts.begin("AutoBackup.maybeRunWeekly")
        defer { PerformanceSignposts.end(interval) }

        guard isEnabled else { return }
        guard (try? resolveDestinationURL()) != nil else { return }

        let lastRun = defaults.object(forKey: lastRunKey) as? Date
        let days: Int = {
            guard let lastRun else { return Int.max }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastRun), to: Calendar.current.startOfDay(for: now)).day ?? Int.max
        }()

        guard days >= 7 else { return }

        do {
            try await runNow(modelContext: modelContext, reason: "weekly", now: now)
        } catch {
            // Non-fatal: user can still export manually.
            logger.error("maybeRunWeekly failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func runNow(modelContext: ModelContext, reason: String, now: Date = Date()) async throws {
        let interval = PerformanceSignposts.begin("AutoBackup.runNow")
        defer { PerformanceSignposts.end(interval, "reason=\(reason)") }

        guard isEnabled else { return }
        let destination = try resolveDestinationURL()

        let encrypted = isEncrypted
        if encrypted, (getEncryptionPassword() ?? "").isEmpty {
            throw AutoBackupError.encryptionPasswordMissing
        }

        let gotAccess = destination.startAccessingSecurityScopedResource()
        defer { if gotAccess { destination.stopAccessingSecurityScopedResource() } }

        let backup = try EscapeBudgetBackupService.makeBackup(modelContext: modelContext)
        let plaintext = try EscapeBudgetBackupService.encode(backup)

        let data: Data
        if encrypted, let password = getEncryptionPassword() {
            data = try EncryptedExportService.encrypt(plaintext: plaintext, password: password)
        } else {
            data = plaintext
        }

        let fileName = primaryFilePrefix + filenameDate(now) + (encrypted ? ".ebbackup" : ".ebbackup")
        let fileURL = destination.appendingPathComponent(fileName)

        try data.write(to: fileURL, options: [.atomic])
        SensitiveFileProtection.apply(to: fileURL, protection: .completeUnlessOpen, excludeFromBackup: false)

        defaults.set(now, forKey: lastRunKey)
        try cleanupOldBackups(in: destination)

        InAppNotificationService.post(
            title: "Auto-backup saved",
            message: "\(fileName) • Saved to \(destination.lastPathComponent)",
            type: .success,
            in: modelContext,
            topic: .backupRestore,
            dedupeKey: "auto_backup.\(reason)",
            minimumInterval: 60 * 60 * 6
        )
    }

    private static func resolveDestinationURL() throws -> URL {
        guard let bookmark = defaults.data(forKey: destinationBookmarkKey) else {
            throw AutoBackupError.destinationNotSet
        }

        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        if stale {
            try setDestination(url: url)
        }

        guard url.hasDirectoryPath else { throw AutoBackupError.destinationUnavailable }
        return url
    }

    private static func filenameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func cleanupOldBackups(in destination: URL) throws {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let backups = urls
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "ebbackup" || ext == "mmbackup" else { return false }
                return filePrefixes.contains { prefix in url.lastPathComponent.hasPrefix(prefix) }
            }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l > r
            }

        guard backups.count > keepCount else { return }
        for url in backups.dropFirst(keepCount) {
            try? fm.removeItem(at: url)
        }
    }
}
