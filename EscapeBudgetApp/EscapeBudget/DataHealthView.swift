import SwiftUI
import SwiftData
import UIKit

struct DataHealthView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var errorCenter: AppErrorCenter
    @Environment(\.appSettings) private var settings

                        
    @State private var auditSummary: DataAuditSummary = .empty
    @State private var storeSummary: StoreSummary = .empty
    @State private var isRunningBackup = false
    @State private var isRunningAudit = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var showAuditAlert = false
    @State private var auditAlertMessage = ""
    @State private var showSelfCheckAlert = false
    @State private var selfCheckAlertMessage = ""

    private struct StoreSummary {
        var appSupportBytes: Int64
        var documentsBytes: Int64
        var appSupportFileCount: Int
        var documentsFileCount: Int

        static let empty = StoreSummary(appSupportBytes: 0, documentsBytes: 0, appSupportFileCount: 0, documentsFileCount: 0)
    }

    private struct DataAuditSummary {
        var lastImportLine: String?
        var lastExportLine: String?
        var lastDeleteLine: String?
        var recentLines: [String]

        static let empty = DataAuditSummary(lastImportLine: nil, lastExportLine: nil, lastDeleteLine: nil, recentLines: [])
    }

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text("Data Health")
                        .appSectionTitleText()
                    Text("A quick overview of your data, storage, and safety net settings.")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)
            }

            Section("Sync") {
                Toggle("Sync with iCloud (Beta)", isOn: $settings.iCloudSyncEnabled)
                Text("If enabled, Escape Budget will attempt to keep your data in sync across your devices. This requires iCloud capabilities in your Apple Developer setup.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Mode") {
                    Text(settings.iCloudSyncEnabled ? "iCloud (Beta)" : "Local only")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Last attempt") {
                    Text(settings.lastSyncAttempt > 0 ? Date(timeIntervalSince1970: settings.lastSyncAttempt).formatted(.dateTime.year().month().day().hour().minute()) : "—")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                LabeledContent("Last success") {
                    Text(settings.lastSyncSuccess > 0 ? Date(timeIntervalSince1970: settings.lastSyncSuccess).formatted(.dateTime.year().month().day().hour().minute()) : "—")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if !settings.lastSyncError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                        Text("Last error")
                            .appCaptionStrongText()
                            .foregroundStyle(.secondary)
                        Text(settings.lastSyncError)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Sync Status")
            } footer: {
                Text("This status reflects the app’s most recent attempt to initialize iCloud-backed storage. Full CloudKit sync requires iCloud/CloudKit entitlements and an enabled container.")
            }

            Section {
                Button {
                    copyDiagnosticsSnapshot()
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                }

                Button {
                    Task { await runDataAudit() }
                } label: {
                    HStack {
                        Label("Run Data Audit", systemImage: "checklist")
                        Spacer()
                        if isRunningAudit {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunningAudit)

                if settings.diagnosticsLastAuditRun > 0 {
                    LabeledContent("Last audit") {
                        Text(Date(timeIntervalSince1970: settings.diagnosticsLastAuditRun).formatted(.dateTime.year().month().day().hour().minute()))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if !settings.diagnosticsLastAuditReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledContent("Last report") {
                        Text(settings.diagnosticsLastAuditReport)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                #if DEBUG
                Button {
                    Task { await runExportImportSelfCheck() }
                } label: {
                    Label("Run Export Self‑Check (Debug)", systemImage: "stethoscope")
                }
                #endif
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Diagnostics are generated locally and avoid sensitive data. You can paste them into a support message if you choose.")
            }

            Section("Storage") {
                LabeledContent("Application Support") {
                    Text(byteCount(storeSummary.appSupportBytes))
                        .monospacedDigit()
                }
                LabeledContent("Documents") {
                    Text(byteCount(storeSummary.documentsBytes))
                        .monospacedDigit()
                }
                LabeledContent("Files (App Support)") { Text("\(storeSummary.appSupportFileCount)") }
                LabeledContent("Files (Documents)") { Text("\(storeSummary.documentsFileCount)") }
            }

            Section("Safety Net") {
                LabeledContent("Auto Backup") {
                    Text(AutoBackupService.destinationDisplayName() == nil ? "Off" : "On")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await runBackupNow() }
                } label: {
                    HStack {
                        Label("Run Backup Now", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if isRunningBackup {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunningBackup || AutoBackupService.destinationDisplayName() == nil || AutoBackupService.isEnabled == false)

                Text("Set up a backup destination in Settings → Data Management → Auto Backup.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Section {
                if let lastImportLine = auditSummary.lastImportLine {
                    auditRow(title: "Last import", value: lastImportLine)
                }
                if let lastExportLine = auditSummary.lastExportLine {
                    auditRow(title: "Last export", value: lastExportLine)
                }
                if let lastDeleteLine = auditSummary.lastDeleteLine {
                    auditRow(title: "Last delete", value: lastDeleteLine)
                }

                if auditSummary.recentLines.isEmpty {
                    Text("No audit events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(auditSummary.recentLines, id: \.self) { line in
                        Text(line)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Audit Trail")
            } footer: {
                Text("The audit log avoids sensitive data and keeps a rolling history for debugging and trust.")
            }
        }
        .appListCompactSpacing()
        .navigationTitle("Data Health")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .alert("Audit Complete", isPresented: $showAuditAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auditAlertMessage)
        }
        .alert("Self‑Check", isPresented: $showSelfCheckAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selfCheckAlertMessage)
        }
        .task {
            refreshSummaries()
        }
        .onChange(of: settings.iCloudSyncEnabled) { _, _ in
            // Container recreation happens in EscapeBudgetApp; keep this view lightweight.
        }
    }

    private func auditRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
            Text(title)
                .appCaptionStrongText()
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppDesign.Theme.Typography.secondaryBody)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func refreshSummaries() {
        storeSummary = computeStoreSummary()
        auditSummary = computeAuditSummary()
    }

    private func copyDiagnosticsSnapshot() {
        let snapshot = buildDiagnosticsSnapshot()
        UIPasteboard.general.string = snapshot
        copiedAlertMessage = "Diagnostics copied to your clipboard."
        showCopiedAlert = true
    }

    private func buildDiagnosticsSnapshot() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundleID = Bundle.main.bundleIdentifier ?? "EscapeBudget"

        let (accounts, categories, groups, transactions, transfers, unpairedTransfers) = fetchBasicCounts()

        var lines: [String] = []
        lines.append("Escape Budget — Diagnostics Snapshot (local-only, redacted)")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("App: \(appVersion) (\(appBuild))")
        lines.append("Bundle: \(bundleID)")
        lines.append("iOS: \(UIDevice.current.systemVersion)")
        lines.append("")
        lines.append("Sync: \(settings.iCloudSyncEnabled ? "iCloud (Beta)" : "Local only")")
        lines.append("Last attempt: \(settings.lastSyncAttempt > 0 ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: settings.lastSyncAttempt)) : "—")")
        lines.append("Last success: \(settings.lastSyncSuccess > 0 ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: settings.lastSyncSuccess)) : "—")")
        if !settings.lastSyncError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Last error: \(sanitizeFreeText(settings.lastSyncError))")
        }
        lines.append("")
        lines.append("Counts:")
        lines.append("- Accounts: \(accounts)")
        lines.append("- Category groups: \(groups)")
        lines.append("- Categories: \(categories)")
        lines.append("- Transactions: \(transactions)")
        lines.append("- Transfer legs: \(transfers)")
        lines.append("- Unpaired transfers: \(unpairedTransfers)")
        lines.append("")
        lines.append("Storage:")
        lines.append("- App Support: \(byteCount(storeSummary.appSupportBytes)) (\(storeSummary.appSupportFileCount) files)")
        lines.append("- Documents: \(byteCount(storeSummary.documentsBytes)) (\(storeSummary.documentsFileCount) files)")
        lines.append("")
        lines.append("Audit (recent):")
        if auditSummary.recentLines.isEmpty {
            lines.append("- No audit events yet.")
        } else {
            for line in auditSummary.recentLines {
                lines.append("- \(sanitizeFreeText(line))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func sanitizeFreeText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "—" }
        value = value.replacingOccurrences(of: "/[^\\s]+", with: "<path>", options: .regularExpression)
        value = value.replacingOccurrences(of: "[A-Za-z]:\\\\[^\\s]+", with: "<path>", options: .regularExpression)
        if value.count > 400 {
            value = String(value.prefix(400)) + "…"
        }
        return value
    }

    private func fetchBasicCounts() -> (accounts: Int, categories: Int, groups: Int, transactions: Int, transferLegs: Int, unpairedTransfers: Int) {
        do {
            let accounts = try modelContext.fetchCount(FetchDescriptor<Account>())
            let groups = try modelContext.fetchCount(FetchDescriptor<CategoryGroup>())
            let categories = try modelContext.fetchCount(FetchDescriptor<Category>())
            let transactions = try modelContext.fetchCount(FetchDescriptor<Transaction>())

            let transferPredicate = #Predicate<Transaction> { $0.transferID != nil }
            let transferLegs = try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: transferPredicate))

            // A "paired" transfer should have 2 legs per transferID. Count transferIDs with != 2 legs.
            let legs = try modelContext.fetch(FetchDescriptor<Transaction>(predicate: transferPredicate))
            var counts: [UUID: Int] = [:]
            for leg in legs {
                guard let id = leg.transferID else { continue }
                counts[id, default: 0] += 1
            }
            let unpaired = counts.values.filter { $0 != 2 }.count

            return (accounts, categories, groups, transactions, transferLegs, unpaired)
        } catch {
            return (0, 0, 0, 0, 0, 0)
        }
    }

    private func runDataAudit() async {
        guard !isRunningAudit else { return }
        isRunningAudit = true
        defer { isRunningAudit = false }

        do {
            let result = try await DataAuditService.run(modelContext: modelContext)
            settings.diagnosticsLastAuditRun = Date().timeIntervalSince1970
            settings.diagnosticsLastAuditReport = result.reportFilename
            refreshSummaries()
            auditAlertMessage = "Saved report: \(result.reportFilename)"
            showAuditAlert = true
        } catch {
            errorCenter.showOperation(.validation, error: error)
        }
    }

    #if DEBUG
    private func runExportImportSelfCheck() async {
        do {
            let exporter = TransactionExporter()
            let transferID = UUID()
            let accountA = Account(name: "Checking", type: .chequing)
            let accountB = Account(name: "Visa", type: .creditCard)

            let tx1 = Transaction(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                payee: "Transfer Out",
                amount: Decimal(-123.45),
                status: .cleared,
                kind: .transfer,
                transferID: transferID,
                account: accountA
            )
            let tx2 = Transaction(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                payee: "Transfer In",
                amount: Decimal(123.45),
                status: .cleared,
                kind: .transfer,
                transferID: transferID,
                account: accountB
            )

            let data = exporter.exportCSVData([tx1, tx2], format: .standard)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("export_selfcheck.csv")
            try data.write(to: url, options: [.atomic])

            var rows: [[String]] = []
            for try await row in RobustCSVParser.parse(url: url) {
                rows.append(row)
                if rows.count >= 3 { break }
            }

            guard let header = rows.first else {
                throw NSError(domain: "SelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "No CSV header row found."])
            }

            guard let transferIDIndex = header.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Transfer ID") == .orderedSame }) else {
                throw NSError(domain: "SelfCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing 'Transfer ID' column in export header."])
            }

            let ids = rows.dropFirst().compactMap { row -> String? in
                guard transferIDIndex < row.count else { return nil }
                let value = row[transferIDIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }

            guard ids.count == 2, ids.allSatisfy({ $0 == transferID.uuidString }) else {
                throw NSError(domain: "SelfCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Transfer ID values did not round‑trip as expected."])
            }

            selfCheckAlertMessage = "Export self‑check passed (Transfer ID column present + values valid)."
            showSelfCheckAlert = true
        } catch {
            errorCenter.showOperation(.validation, error: error)
        }
    }
    #endif

    private func runBackupNow() async {
        guard !isRunningBackup else { return }
        isRunningBackup = true
        defer { isRunningBackup = false }

        do {
            try await AutoBackupService.runNow(modelContext: modelContext, reason: "manual")
            refreshSummaries()
        } catch {
            errorCenter.showOperation(.export, error: error)
        }
    }

    private func computeStoreSummary() -> StoreSummary {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first

        let appSupportResult = folderStats(url: appSupport)
        let documentsResult = folderStats(url: documents)

        return StoreSummary(
            appSupportBytes: appSupportResult.bytes,
            documentsBytes: documentsResult.bytes,
            appSupportFileCount: appSupportResult.fileCount,
            documentsFileCount: documentsResult.fileCount
        )
    }

    private func folderStats(url: URL?) -> (bytes: Int64, fileCount: Int) {
        guard let url else { return (0, 0) }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return (0, 0)
        }

        var bytes: Int64 = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true {
                bytes += Int64(values.fileSize ?? 0)
                fileCount += 1
            }
        }

        return (bytes, fileCount)
    }

    private func computeAuditSummary() -> DataAuditSummary {
        let fm = FileManager.default
        let bundle = Bundle.main.bundleIdentifier ?? "EscapeBudget"
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundle, isDirectory: true)
        let url = base?.appendingPathComponent("security_audit.log")

        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return .empty
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        func lastLine(containing token: String) -> String? {
            lines.last(where: { $0.contains(token) })
        }

        let recent = Array(lines.suffix(10))
        return DataAuditSummary(
            lastImportLine: lastLine(containing: "] [DATA] import"),
            lastExportLine: lastLine(containing: "] [DATA] export"),
            lastDeleteLine: lastLine(containing: "] [DATA] delete"),
            recentLines: recent
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        DataHealthView()
    }
    .environmentObject(AppErrorCenter.shared)
}
