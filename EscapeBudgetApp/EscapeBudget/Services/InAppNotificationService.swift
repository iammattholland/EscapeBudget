import Foundation
import SwiftData
import UserNotifications

@MainActor
enum InAppNotificationService {
    private static let lastSentPrefix = "inAppNotifications.lastSent."

    static func post(
        _ notification: AppNotification,
        in modelContext: ModelContext,
        topic: NotificationTopic,
        dedupeKey: String? = nil,
        minimumInterval: TimeInterval? = nil
    ) {
        guard topic.isEnabled() else { return }

        if let dedupeKey {
            let interval = minimumInterval ?? 0
            guard shouldSend(dedupeKey: dedupeKey, minimumInterval: interval) else { return }
            markSent(dedupeKey: dedupeKey)
        }

        modelContext.insert(notification)
        let saved = modelContext.safeSave(context: "InAppNotificationService.post", showErrorToUser: false)
        guard saved else {
            modelContext.delete(notification)
            return
        }

        UserDefaults.standard.set(true, forKey: "hasNotifications")

        Task {
            await scheduleLocalNotificationIfPermitted(
                title: notification.title,
                message: notification.message,
                identifier: notificationIdentifier(notification: notification, dedupeKey: dedupeKey)
            )
        }
    }

    static func post(
        title: String,
        message: String,
        type: NotificationType = .info,
        in modelContext: ModelContext,
        topic: NotificationTopic,
        dedupeKey: String? = nil,
        minimumInterval: TimeInterval? = nil
    ) {
        let note = AppNotification(title: title, message: message, date: Date(), type: type, isRead: false)
        post(note, in: modelContext, topic: topic, dedupeKey: dedupeKey, minimumInterval: minimumInterval)
    }

    private static func shouldSend(dedupeKey: String, minimumInterval: TimeInterval) -> Bool {
        guard minimumInterval > 0 else {
            return UserDefaults.standard.object(forKey: lastSentPrefix + dedupeKey) == nil
        }

        if let last = UserDefaults.standard.object(forKey: lastSentPrefix + dedupeKey) as? Date {
            return Date().timeIntervalSince(last) >= minimumInterval
        }

        return true
    }

    private static func markSent(dedupeKey: String) {
        UserDefaults.standard.set(Date(), forKey: lastSentPrefix + dedupeKey)
    }

    private static func notificationIdentifier(notification: AppNotification, dedupeKey: String?) -> String {
        if let dedupeKey, !dedupeKey.isEmpty {
            return "inapp.\(dedupeKey)"
        }
        return "inapp.\(notification.id.uuidString)"
    }

    private static func scheduleLocalNotificationIfPermitted(title: String, message: String, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let showSensitive = UserDefaults.standard.object(forKey: "notifications.showSensitiveContent") as? Bool ?? false

        let content = UNMutableNotificationContent()
        content.title = title
        if showSensitive {
            if let range = message.range(of: " • ") {
                let first = String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty, !rest.isEmpty {
                    content.subtitle = first
                    content.body = rest
                } else {
                    content.body = message
                }
            } else {
                content.body = message
            }
        } else {
            content.subtitle = ""
            content.body = "Open Escape\u{00A0}Budget to view details."
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Non-fatal: in-app notification has already been recorded.
        }
    }
}
