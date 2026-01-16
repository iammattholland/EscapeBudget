import SwiftUI
import SwiftData

@Model
final class AppNotification: DemoDataTrackable {
    var id: UUID
    var title: String
    var message: String
    var date: Date
    var isRead: Bool
    var type: NotificationType
    var isDemoData: Bool = false
    
    init(title: String, message: String, date: Date = Date(), type: NotificationType = .info, isRead: Bool = false, isDemoData: Bool = false) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.date = date
        self.type = type
        self.isRead = isRead
        self.isDemoData = isDemoData
    }
}

enum NotificationTopic: String, Codable, CaseIterable, Identifiable {
    case budgetAlerts
    case billReminders
    case transfersInbox
    case reconcileReminders
    case importComplete
    case exportStatus
    case backupRestore
    case ruleApplied
    case badgeAchievements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budgetAlerts: return "Budget Alerts"
        case .billReminders: return "Bill Reminders"
        case .transfersInbox: return "Transfers Inbox"
        case .reconcileReminders: return "Reconcile Reminders"
        case .importComplete: return "Import Complete"
        case .exportStatus: return "Export Status"
        case .backupRestore: return "Backup & Restore"
        case .ruleApplied: return "Rule Applied"
        case .badgeAchievements: return "Badge Achievements"
        }
    }

    var settingsKey: String {
        switch self {
        case .budgetAlerts:
            return "budgetAlerts"
        case .billReminders:
            return "billReminders"
        case .transfersInbox:
            return "notifications.transfersInbox"
        case .reconcileReminders:
            return "notifications.reconcileReminders"
        case .importComplete:
            return "notifications.importComplete"
        case .exportStatus:
            return "notifications.exportStatus"
        case .backupRestore:
            return "notifications.backupRestore"
        case .ruleApplied:
            return "notifications.ruleApplied"
        case .badgeAchievements:
            return "notifications.badges"
        }
    }

    var defaultEnabled: Bool { true }

    func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: settingsKey) as? Bool {
            return stored
        }
        return defaultEnabled
    }
}

enum NotificationType: String, Codable {
    case info
    case success
    case warning
    case alert
    
    var icon: String {
        switch self {
        case .info: return "bell.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .alert: return "exclamationmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .info: return "blue"
        case .success: return "green"
        case .warning: return "orange"
        case .alert: return "red"
        }
    }
}
