import Foundation

enum DataChangeTracker {
    static let didChangeNotification = Notification.Name("EscapeBudget.DataDidChange")

    private static let tokenKey = "EscapeBudget.dataChangeToken"
    private static let postCoalesceInterval: TimeInterval = 0.08
    private static let syncQueue = DispatchQueue(label: "EscapeBudget.DataChangeTracker.sync")
    private static var pendingPost = false

    static var token: Int {
        UserDefaults.standard.integer(forKey: tokenKey)
    }

    static func bump() {
        PerformanceSignposts.event("DataChangeTracker.bump")
        let next = token &+ 1
        UserDefaults.standard.set(next, forKey: tokenKey)

        syncQueue.async {
            guard !pendingPost else { return }
            pendingPost = true
            DispatchQueue.main.asyncAfter(deadline: .now() + postCoalesceInterval) {
                syncQueue.async {
                    pendingPost = false
                }
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }
}
