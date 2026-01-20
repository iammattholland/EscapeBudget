import Foundation
import os.log

/// Centralized security event logging for audit trails and incident investigation.
/// Logs security-relevant events without exposing sensitive data.
final class SecurityLogger {
    static let shared = SecurityLogger()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget", category: "Security")
    private var fileLogger: FileHandle?
    private let logFileURL: URL?
    private let queue = DispatchQueue(label: "com.escapebudget.securitylogger", qos: .utility)

    private init() {
        // Create secure log file in app's Application Support directory
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appSupportDirectory = appSupportPath?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "EscapeBudget", isDirectory: true)
        if let appSupportDirectory {
            try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        logFileURL = appSupportDirectory?.appendingPathComponent("security_audit.log")

        if var url = logFileURL {
            // Migrate any legacy log from Documents (best-effort).
            let legacyURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent(".security_audit.log")
            if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.moveItem(at: legacyURL, to: url)
                } else {
                    try? FileManager.default.removeItem(at: legacyURL)
                }
            }

            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                // Set file protection
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: url.path
                )
            }
            // Prevent audit logs from being backed up / exported.
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)

            fileLogger = try? FileHandle(forWritingTo: url)
            fileLogger?.seekToEndOfFile()
        } else {
            fileLogger = nil
        }
    }

    deinit {
        try? fileLogger?.close()
    }

    func resetAuditLog() {
        queue.sync {
            try? fileLogger?.close()
            fileLogger = nil

            guard var url = logFileURL else { return }
            try? FileManager.default.removeItem(at: url)

            FileManager.default.createFile(atPath: url.path, contents: nil)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: url.path
            )

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)

            fileLogger = try? FileHandle(forWritingTo: url)
            fileLogger?.seekToEndOfFile()
        }
    }

    // MARK: - Authentication Events

    func logAuthenticationAttempt(success: Bool, method: String) {
        let event = SecurityEvent(
            type: .authentication,
            action: success ? "auth_success" : "auth_failure",
            details: ["method": method]
        )
        log(event)
    }

    func logBiometricEnabled() {
        let event = SecurityEvent(
            type: .settingsChange,
            action: "biometric_enabled",
            details: [:]
        )
        log(event)
    }

    func logBiometricDisabled() {
        let event = SecurityEvent(
            type: .settingsChange,
            action: "biometric_disabled",
            details: [:]
        )
        log(event)
    }

    // MARK: - Data Events

    func logDataImport(rowCount: Int, source: String) {
        let event = SecurityEvent(
            type: .dataOperation,
            action: "import",
            details: ["row_count": String(rowCount), "source": source]
        )
        log(event)
    }

    func logDataExport(rowCount: Int, encrypted: Bool = false) {
        let event = SecurityEvent(
            type: .dataOperation,
            action: "export",
            details: ["row_count": String(rowCount), "encrypted": encrypted ? "true" : "false"]
        )
        log(event)
    }

    func logDataAudit() {
        let event = SecurityEvent(
            type: .dataOperation,
            action: "audit",
            details: [:]
        )
        log(event)
    }

    func logDataDeletion(entityType: String, count: Int) {
        let event = SecurityEvent(
            type: .dataOperation,
            action: "delete",
            details: ["entity_type": entityType, "count": String(count)]
        )
        log(event)
    }

    func logDemoModeToggle(enabled: Bool) {
        let event = SecurityEvent(
            type: .settingsChange,
            action: enabled ? "demo_mode_enabled" : "demo_mode_disabled",
            details: [:]
        )
        log(event)
    }

    // MARK: - Error Events

    func logSecurityError(_ error: Error, context: String) {
        let nsError = error as NSError
        let event = SecurityEvent(
            type: .error,
            action: "security_error",
            details: [
                "context": context,
                "error_type": String(describing: type(of: error)),
                "error_domain": nsError.domain,
                "error_code": String(nsError.code)
            ]
        )
        log(event)

        // Also log to system logger for debugging (without sensitive details)
        logger.error("Security error in \(context): \(String(describing: type(of: error)))")
    }

    func logFileOperationError(operation: String, path: String) {
        // Don't log full path for security, just the operation and filename
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let event = SecurityEvent(
            type: .error,
            action: "file_operation_failed",
            details: ["operation": operation, "filename": filename]
        )
        log(event)
    }

    // MARK: - App Lifecycle

    func logAppLaunch() {
        let event = SecurityEvent(
            type: .lifecycle,
            action: "app_launch",
            details: [:]
        )
        log(event)
    }

    func logAppBackground() {
        let event = SecurityEvent(
            type: .lifecycle,
            action: "app_background",
            details: [:]
        )
        log(event)
    }

    func logAppForeground() {
        let event = SecurityEvent(
            type: .lifecycle,
            action: "app_foreground",
            details: [:]
        )
        log(event)
    }

    // MARK: - Private

    private func log(_ event: SecurityEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let logLine = event.formattedLogLine()

            // Log to system log (privacy-safe)
            self.logger.info("\(event.type.rawValue): \(event.action)")

            // Log to file for audit trail
            if let data = (logLine + "\n").data(using: .utf8) {
                self.fileLogger?.write(data)
            }

            // Trim log file if too large (keep last 10000 lines / ~1MB)
            self.trimLogFileIfNeeded()
        }
    }

    private func trimLogFileIfNeeded() {
        guard let url = logFileURL else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > 1_000_000 { // 1MB
                // Read file, keep last 5000 lines
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                let trimmedLines = Array(lines.suffix(5000))
                let trimmedContent = trimmedLines.joined(separator: "\n")
                try trimmedContent.write(to: url, atomically: true, encoding: .utf8)

                // Re-open handle after rewrite so future writes append correctly.
                try? fileLogger?.close()
                fileLogger = try? FileHandle(forWritingTo: url)
                fileLogger?.seekToEndOfFile()
            }
        } catch {
            // Silently fail - logging shouldn't crash the app
        }
    }
}

// MARK: - Security Event Model

private struct SecurityEvent {
    enum EventType: String {
        case authentication = "AUTH"
        case dataOperation = "DATA"
        case settingsChange = "SETTINGS"
        case error = "ERROR"
        case lifecycle = "LIFECYCLE"
    }

    let timestamp: Date
    let type: EventType
    let action: String
    let details: [String: String]

    init(type: EventType, action: String, details: [String: String]) {
        self.timestamp = Date()
        self.type = type
        self.action = action
        self.details = details
    }

    func formattedLogLine() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampStr = formatter.string(from: timestamp)

        var line = "[\(timestampStr)] [\(type.rawValue)] \(action)"

        if !details.isEmpty {
            let detailsStr = details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            line += " {\(detailsStr)}"
        }

        return line
    }
}
