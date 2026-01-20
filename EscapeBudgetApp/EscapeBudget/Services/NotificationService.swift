import Foundation
@preconcurrency import UserNotifications
import Combine
import SwiftData
import os.log

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var notificationsEnabled = false
    @Published var reminderDaysBefore = 1
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget", category: "Notifications")

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            notificationsEnabled = granted
            return granted
        } catch {
            logger.error("Authorization error: \(error, privacy: .private)")
            notificationsEnabled = false
            return false
        }
    }

    func scheduleRecurringBillNotifications(for purchases: [RecurringPurchase], daysBefore: Int = 1) async {
        guard notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let showSensitive = UserDefaults.standard.object(forKey: "notifications.showSensitiveContent") as? Bool ?? false

        // Remove existing recurring bill notifications
        center.removePendingNotificationRequests(withIdentifiers: purchases.map { "recurring-\($0.persistentModelID)" })

        let calendar = Calendar.current

        for purchase in purchases where purchase.isActive {
            let notificationDate = calendar.date(byAdding: .day, value: -daysBefore, to: purchase.nextDate)

            guard let notificationDate = notificationDate, notificationDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = showSensitive ? "Upcoming Bill: \(purchase.name)" : "Upcoming Bill"

            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
            let amountString = formatter.string(from: purchase.amount as NSDecimalNumber) ?? "\(purchase.amount)"

            if showSensitive {
                if daysBefore == 0 {
                    content.body = "\(amountString) due today"
                } else if daysBefore == 1 {
                    content.body = "\(amountString) due tomorrow"
                } else {
                    content.body = "\(amountString) due in \(daysBefore) days"
                }
            } else {
                if daysBefore == 0 {
                    content.body = "A bill is due today. Open Escape\u{00A0}Budget for details."
                } else if daysBefore == 1 {
                    content.body = "A bill is due tomorrow. Open Escape\u{00A0}Budget for details."
                } else {
                    content.body = "A bill is due soon. Open Escape\u{00A0}Budget for details."
                }
            }

            content.categoryIdentifier = "RECURRING_BILL"
            content.sound = .default

            let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

            let request = UNNotificationRequest(
                identifier: "recurring-\(purchase.persistentModelID)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                let id = String(describing: purchase.persistentModelID)
                logger.error("Scheduling failed for recurring purchase \(id, privacy: .public): \(error, privacy: .private)")
            }
        }
    }

    func scheduleAllRecurringBillNotifications(modelContext: ModelContext, daysBefore: Int = 1) async {
        let descriptor = FetchDescriptor<RecurringPurchase>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let purchases = try modelContext.fetch(descriptor)
            await scheduleRecurringBillNotifications(for: purchases, daysBefore: daysBefore)
        } catch {
            logger.error("Fetch failed: \(error, privacy: .private)")
        }
    }

    func cancelAllRecurringBillNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let recurringIDs = requests
                .filter { $0.identifier.hasPrefix("recurring-") }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: recurringIDs)
        }
    }
}
