import Foundation
import SwiftData
import UIKit

@MainActor
enum DiagnosticsService {
    enum Severity: String {
        case info
        case warning
        case error
    }

    static func recordError(
        _ error: Error,
        title: String,
        message: String,
        area: String,
        operation: String? = nil,
        context: [String: String] = [:],
        in modelContext: ModelContext,
        isDemoData: Bool = false
    ) {
        let nsError = error as NSError
        let sanitizedMessage = sanitizeMessage(message)
        let sanitizedContext = sanitizeContext(context)

        let entry = DiagnosticEvent(
            area: sanitizeTag(area),
            severity: Severity.error.rawValue,
            title: sanitizeTitle(title),
            message: sanitizedMessage,
            operation: operation.map(sanitizeTag),
            errorType: String(describing: type(of: error)),
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            osVersion: UIDevice.current.systemVersion,
            contextJSON: encodeContextJSON(sanitizedContext),
            isDemoData: isDemoData
        )

        modelContext.insert(entry)
        trimIfNeeded(in: modelContext, isDemoData: isDemoData)
        _ = modelContext.safeSave(context: "DiagnosticsService.recordError", showErrorToUser: false)
    }

    static func recordEvent(
        title: String,
        message: String,
        area: String,
        severity: Severity = .info,
        operation: String? = nil,
        context: [String: String] = [:],
        in modelContext: ModelContext,
        isDemoData: Bool = false
    ) {
        let sanitizedContext = sanitizeContext(context)
        let entry = DiagnosticEvent(
            area: sanitizeTag(area),
            severity: severity.rawValue,
            title: sanitizeTitle(title),
            message: sanitizeMessage(message),
            operation: operation.map(sanitizeTag),
            errorType: nil,
            errorDomain: nil,
            errorCode: nil,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            osVersion: UIDevice.current.systemVersion,
            contextJSON: encodeContextJSON(sanitizedContext),
            isDemoData: isDemoData
        )

        modelContext.insert(entry)
        trimIfNeeded(in: modelContext, isDemoData: isDemoData)
        _ = modelContext.safeSave(context: "DiagnosticsService.recordEvent", showErrorToUser: false)
    }

    static func copyReportToClipboard(events: [DiagnosticEvent]) {
        let lines = reportLines(events: events)
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func trimIfNeeded(in modelContext: ModelContext, isDemoData: Bool) {
        // Keep last 200 events per mode.
        let predicate = #Predicate<DiagnosticEvent> { $0.isDemoData == isDemoData }
        let descriptor = FetchDescriptor<DiagnosticEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let events = try? modelContext.fetch(descriptor), events.count > 200 else { return }
        for event in events.suffix(from: 200) {
            modelContext.delete(event)
        }
    }

    private static func reportLines(events: [DiagnosticEvent]) -> [String] {
        var lines: [String] = []
        lines.append("Escape Budget Diagnostics (local-only, redacted)")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Events: \(events.count)")
        lines.append("")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for event in events.prefix(200) {
            let timestamp = formatter.string(from: event.timestamp)
            var head = "[\(timestamp)] [\(event.severity.uppercased())] \(event.area)"
            if let operation = event.operation, !operation.isEmpty {
                head += " op=\(operation)"
            }
            lines.append(head)
            lines.append("title=\(event.title)")
            lines.append("message=\(event.message)")
            if let domain = event.errorDomain, let code = event.errorCode {
                lines.append("error=\(domain)#\(code) type=\(event.errorType ?? "Unknown")")
            }
            if let appVersion = event.appVersion, let appBuild = event.appBuild {
                lines.append("app=\(appVersion) (\(appBuild)) ios=\(event.osVersion ?? "?")")
            }
            if let ctx = event.contextJSON, !ctx.isEmpty {
                lines.append("context=\(ctx)")
            }
            lines.append("---")
        }

        return lines
    }

    private static func encodeContextJSON(_ context: [String: String]) -> String? {
        guard !context.isEmpty else { return nil }
        let limited = Dictionary(uniqueKeysWithValues: Array(context.prefix(24)))
        guard let data = try? JSONSerialization.data(withJSONObject: limited, options: [.sortedKeys]),
              var string = String(data: data, encoding: .utf8) else { return nil }
        if string.count > 800 {
            string = String(string.prefix(800)) + "…"
        }
        return string
    }

    private static func sanitizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Error" }
        return String(trimmed.prefix(120))
    }

    private static func sanitizeTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "unknown" }
        return String(trimmed.prefix(40))
    }

    private static func sanitizeMessage(_ message: String) -> String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "An error occurred." }

        // Keep single-line to avoid clipboard formatting surprises.
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Remove file paths.
        text = text.replacingOccurrences(of: "/[^\\s]+", with: "<path>", options: .regularExpression)
        text = text.replacingOccurrences(of: "[A-Za-z]:\\\\[^\\s]+", with: "<path>", options: .regularExpression)

        // Remove obvious email addresses.
        text = text.replacingOccurrences(
            of: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            with: "<email>",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove long numeric sequences (account numbers, IDs).
        text = text.replacingOccurrences(
            of: "\\b\\d{9,}\\b",
            with: "<number>",
            options: [.regularExpression]
        )

        if text.count > 300 {
            text = String(text.prefix(300)) + "…"
        }
        return text
    }

    private static func sanitizeContext(_ context: [String: String]) -> [String: String] {
        guard !context.isEmpty else { return context }

        let sensitiveKeyFragments: [String] = [
            "payee", "memo", "note", "description", "merchant",
            "account", "category", "tag", "item", "name",
            "amount", "balance", "currency", "receipt", "image",
            "filepath", "path", "url"
        ]

        var sanitized: [String: String] = [:]
        for (rawKey, rawValue) in context {
            let key = sanitizeTag(rawKey)
            let lower = key.lowercased()
            let isSensitiveKey = sensitiveKeyFragments.contains { lower.contains($0) }
            sanitized[key] = isSensitiveKey ? "<redacted>" : sanitizeMessage(rawValue)
        }
        return sanitized
    }
}
