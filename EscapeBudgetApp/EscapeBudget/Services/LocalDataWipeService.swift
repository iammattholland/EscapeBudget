import Foundation

/// Best-effort deletion of local artifacts so "Delete All Data" truly resets the app.
/// This intentionally avoids touching system-managed keys/files.
enum LocalDataWipeService {
    static func wipeLocalFiles() {
        wipeTemporaryDirectory()
        wipeAppSupportArtifacts()
    }

    static func wipeUserDefaults() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys

        let prefixesToRemove: [String] = [
            "retirement.",
            "cashflow.",
            "forecast.",
            "budget.",
            "backup.",
            "export.",
            "import.",
            "sync.",
            "security.",
            "notifications.",
            "badge.",
            "badges.",
            "inAppNotifications.",
            AppSettings.Keys.hasNotifications,
            AppSettings.Keys.isDemoMode,
            AppSettings.Keys.showTransactionTags,
            AppSettings.Keys.weekStartDay,
            AppSettings.Keys.currencyCode,
            AppSettings.Keys.appLanguage,
            AppSettings.Keys.userAppearance,
            AppSettings.Keys.appIconMode,
            AppSettings.Keys.appColorMode
        ]

        for key in keys {
            if prefixesToRemove.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Private

    private static func wipeTemporaryDirectory() {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        guard let urls = try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for url in urls {
            try? fm.removeItem(at: url)
        }
    }

    private static func wipeAppSupportArtifacts() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let base = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "EscapeBudget", isDirectory: true)

        // Remove privacy-sensitive diagnostics and audit logs (best-effort).
        let urlsToRemove: [URL] = [
            base.appendingPathComponent("diagnostics", isDirectory: true)
        ]

        for url in urlsToRemove {
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }
}
