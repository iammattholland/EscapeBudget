import Foundation
import SwiftData

@MainActor
enum DataAuditService {
    struct Result {
        let reportURL: URL
        let reportFilename: String
    }

    static func run(modelContext: ModelContext) async throws -> Result {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let filename = "data_audit_\(formatter.string(from: now)).txt"
        var reportURL = try makeDiagnosticsDirectory().appendingPathComponent(filename)

        let lines = try buildReportLines(modelContext: modelContext, generatedAt: now)
        let content = lines.joined(separator: "\n") + "\n"

        try content.write(to: reportURL, atomically: true, encoding: .utf8)

        // Protect and exclude from backup.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: reportURL.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? reportURL.setResourceValues(values)

        SecurityLogger.shared.logDataAudit()

        return Result(reportURL: reportURL, reportFilename: filename)
    }

    // MARK: - Private

    private static func makeDiagnosticsDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "EscapeBudget", isDirectory: true)
        let diagnostics = base?.appendingPathComponent("diagnostics", isDirectory: true)
        guard let diagnostics else {
            throw NSError(domain: "DataAuditService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Application Support directory."])
        }
        try fm.createDirectory(at: diagnostics, withIntermediateDirectories: true, attributes: nil)
        return diagnostics
    }

    private static func buildReportLines(modelContext: ModelContext, generatedAt: Date) throws -> [String] {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let accounts = try modelContext.fetchCount(FetchDescriptor<Account>())
        let groups = try modelContext.fetchCount(FetchDescriptor<CategoryGroup>())
        let categories = try modelContext.fetchCount(FetchDescriptor<Category>())
        let transactions = try modelContext.fetchCount(FetchDescriptor<Transaction>())

        let transferPredicate = #Predicate<Transaction> { $0.transferID != nil }
        let transferLegs = try modelContext.fetch(FetchDescriptor<Transaction>(predicate: transferPredicate))

        var transferLegsByID: [UUID: Int] = [:]
        var transferLegsMissingAccount = 0
        for leg in transferLegs {
            if leg.account == nil { transferLegsMissingAccount += 1 }
            if let id = leg.transferID {
                transferLegsByID[id, default: 0] += 1
            }
        }

        let unpairedTransferIDs = transferLegsByID.filter { $0.value != 2 }.count
        let largestTransferGroup = transferLegsByID.values.max() ?? 0

        // High-level transaction hygiene (no PII).
        // Use raw string literal inside #Predicate to avoid macro limitations with enum cases.
        let kindPredicate = #Predicate<Transaction> { $0.kindRawValue != "Standard" }
        let nonStandardTransactions = try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: kindPredicate))

        let uncategorizedPredicate = #Predicate<Transaction> { $0.kindRawValue == "Standard" && $0.category == nil }
        let uncategorizedTransactions = try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: uncategorizedPredicate))

        let missingAccountPredicate = #Predicate<Transaction> { $0.account == nil }
        let missingAccountTransactions = try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: missingAccountPredicate))

        var lines: [String] = []
        lines.append("Escape Budget — Data Audit (local-only, redacted)")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("App: \(appVersion) (\(appBuild))")
        lines.append("")
        lines.append("Counts:")
        lines.append("- Accounts: \(accounts)")
        lines.append("- Category groups: \(groups)")
        lines.append("- Categories: \(categories)")
        lines.append("- Transactions: \(transactions)")
        lines.append("- Non-standard transactions: \(nonStandardTransactions)")
        lines.append("- Uncategorized (standard) transactions: \(uncategorizedTransactions)")
        lines.append("- Missing-account transactions: \(missingAccountTransactions)")
        lines.append("")
        lines.append("Transfers:")
        lines.append("- Transfer legs: \(transferLegs.count)")
        lines.append("- Transfer IDs with != 2 legs: \(unpairedTransferIDs)")
        lines.append("- Largest legs for a single Transfer ID: \(largestTransferGroup)")
        lines.append("- Transfer legs missing account: \(transferLegsMissingAccount)")
        lines.append("")
        lines.append("Notes:")
        lines.append("- This report intentionally omits payees, memos, and account names.")

        return lines
    }
}
