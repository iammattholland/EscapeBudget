import Foundation

enum DataChangeTracker {
    static let didChangeNotification = Notification.Name("EscapeBudget.DataDidChange")

    private static let tokenKey = "EscapeBudget.dataChangeToken"

    static var token: Int {
        UserDefaults.standard.integer(forKey: tokenKey)
    }

    static func bump() {
        let next = token &+ 1
        UserDefaults.standard.set(next, forKey: tokenKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

