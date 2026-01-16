import Combine
import Foundation

@MainActor
final class PremiumStatusService: ObservableObject {
    static let shared = PremiumStatusService()

    enum Plan: Equatable {
        case trial(daysRemaining: Int)
        case premium
        case free
    }

    @Published private(set) var plan: Plan = .trial(daysRemaining: 0)

    private let keychain = KeychainService.shared
    private let calendar = Calendar.current

    /// Change this to 60 when you decide.
    private let trialLengthDays: Int = 30

    private init() {
        refresh()
    }

    func refresh(now: Date = Date()) {
        if keychain.getString(forKey: .premiumEntitlement) == "premium" {
            plan = .premium
            return
        }

        let start = trialStartDate(now: now)
        let end = calendar.date(byAdding: .day, value: trialLengthDays, to: start) ?? start
        let daysRemaining = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0)
        plan = daysRemaining > 0 ? .trial(daysRemaining: daysRemaining) : .free
    }

    func ensureTrialStarted(now: Date = Date()) {
        _ = trialStartDate(now: now)
        refresh(now: now)
    }

    func setPremiumOverride(enabled: Bool) {
        if enabled {
            _ = keychain.setString("premium", forKey: .premiumEntitlement)
        } else {
            keychain.remove(forKey: .premiumEntitlement)
        }
        refresh()
    }

    private func trialStartDate(now: Date) -> Date {
        if let raw = keychain.getString(forKey: .trialStartISO8601),
           let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let raw = formatter.string(from: now)
        _ = keychain.setString(raw, forKey: .trialStartISO8601)
        return now
    }
}
