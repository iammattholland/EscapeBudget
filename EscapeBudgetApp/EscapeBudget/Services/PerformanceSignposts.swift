import Foundation
import os

enum PerformanceSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mattholland.EscapeBudget"
    private static let logger = Logger(subsystem: subsystem, category: "performance")
    private static let signposter = OSSignposter(subsystem: subsystem, category: "performance")

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        fileprivate let clockStart: ContinuousClock.Instant
    }

    static func begin(_ name: StaticString) -> Interval {
        let intervalState = signposter.beginInterval(name, id: .exclusive)
        return Interval(name: name, state: intervalState, clockStart: ContinuousClock().now)
    }

    static func end(_ interval: Interval, _ message: String? = nil) {
        signposter.endInterval(interval.name, interval.state)
        if let message {
            let duration = interval.clockStart.duration(to: ContinuousClock().now)
            logger.debug("\(interval.name, privacy: .public) \(message, privacy: .public) (\(duration))")
        }
    }

    @discardableResult
    static func withInterval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let interval = begin(name)
        defer { end(interval) }
        return try work()
    }

    @discardableResult
    static func withInterval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let interval = begin(name)
        defer { end(interval) }
        return try await work()
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name, id: .exclusive)
    }
}
