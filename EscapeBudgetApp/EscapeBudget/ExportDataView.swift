import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case standard = "Standard CSV"
    case ynab = "YNAB Format"
    case mint = "Mint Format"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .standard: return "Compatible with most apps"
        case .ynab: return "Optimized for YNAB import"
        case .mint: return "Mint.com compatible format"
        }
    }
}

enum ExportDateRange: String, CaseIterable, Identifiable {
    case all = "All Time"
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case last6Months = "Last 6 Months"
    case lastYear = "Last Year"
    case thisYear = "This Year"
    case custom = "Custom Range"

    var id: String { rawValue }
}

struct ExportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("export.encrypted") private var isEncryptedExport = true
    @AppStorage("export.plaintextConfirmed") private var exportPlaintextConfirmed = false
    @Environment(\.appColorMode) private var appColorMode

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var selectedFormat: ExportFormat = .standard
    @State private var selectedDateRange: ExportDateRange = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showCustomDatePicker = false
    @State private var exportPassword = ""
    @State private var exportPasswordConfirm = ""
    @State private var showingEncryptionWarning = false
    @State private var showingPlaintextWarning = false
    @State private var bypassPlaintextWarning = false
    @State private var pendingPlaintextAction: PendingPlaintextAction? = nil
    @State private var exportProgress: OperationProgressState? = nil
    @State private var currentExportTask: Task<Void, Never>? = nil

    /// Filtered transactions excluding demo data
    private var exportableTransactions: [Transaction] {
        let nonDemoTransactions = transactions.filter { !$0.isDemoData }

        // Apply date filtering
        let calendar = Calendar.current
        let now = Date()

        switch selectedDateRange {
        case .all:
            return nonDemoTransactions
        case .lastMonth:
            let startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return nonDemoTransactions.filter { $0.date >= startDate }
        case .last3Months:
            let startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return nonDemoTransactions.filter { $0.date >= startDate }
        case .last6Months:
            let startDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return nonDemoTransactions.filter { $0.date >= startDate }
        case .lastYear:
            let startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return nonDemoTransactions.filter { $0.date >= startDate }
        case .thisYear:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            return nonDemoTransactions.filter { $0.date >= startOfYear }
        case .custom:
            let startOfDay = calendar.startOfDay(for: customStartDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return nonDemoTransactions.filter { $0.date >= startOfDay && $0.date <= endOfDay }
        }
    }

    private var isEncryptedExportReady: Bool {
        guard isEncryptedExport else { return true }
        guard exportPassword.count >= 8 else { return false }
        return exportPassword == exportPasswordConfirm
    }

    private enum PendingPlaintextAction {
        case transactions
        case backup
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Transactions")
                            .font(.headline)
                        Text("Export your transactions to CSV, with optional password protection.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Label("\(exportableTransactions.count) Transactions", systemImage: "list.bullet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if isDemoMode {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.warning(for: appColorMode))
                            Text("Demo mode is active. Demo data will not be exported.")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            VStack(alignment: .leading) {
                                Text(format.rawValue)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.automatic)
                }

                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRange) {
                        ForEach(ExportDateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.automatic)

                    if selectedDateRange == .custom {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    }
                }

                Section("Security") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Password-protected export", isOn: encryptedExportBinding)
                        Text("Encrypts the export file with your password.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isEncryptedExport {
                        SecureField("Password (min 8 characters)", text: $exportPassword)
                            .textContentType(.newPassword)
                        SecureField("Confirm password", text: $exportPasswordConfirm)
                            .textContentType(.newPassword)

                        if !exportPassword.isEmpty, exportPassword.count < 8 {
                            Text("Use at least 8 characters.")
                                .font(.caption)
                                .foregroundStyle(AppColors.warning(for: appColorMode))
                        } else if !exportPasswordConfirm.isEmpty, exportPasswordConfirm != exportPassword {
                            Text("Passwords don’t match.")
                                .font(.caption)
                                .foregroundStyle(AppColors.danger(for: appColorMode))
                        }

                        Text("If you forget this password, the export can’t be recovered.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    if isExporting {
                        HStack {
                            ProgressView()
                            Text("Preparing export...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: exportData) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export \(exportableTransactions.count) Transactions")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(exportableTransactions.isEmpty || !isEncryptedExportReady)
                    }
                }

                Section("Escape Budget Backup") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export a full backup of your accounts, budgets, tags, goals, rules, and transactions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Restore it later via Settings → Data Management → Restore Backup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        exportBackup()
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive")
                            Text("Export Full Backup")
                            Spacer()
                        }
                    }
                    .disabled(isExporting || !isEncryptedExportReady)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url]) {
                        cleanupExportedFile()
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Password Protection", isPresented: $showingEncryptionWarning) {
                Button("Cancel", role: .cancel) {
                    isEncryptedExport = false
                    exportPassword = ""
                    exportPasswordConfirm = ""
                }
                Button("Continue") {
                    isEncryptedExport = true
                }
            } message: {
                Text("If you forget this password, the export can’t be recovered.")
            }
            .alert("Plaintext Export", isPresented: $showingPlaintextWarning) {
                Button("Cancel", role: .cancel) {
                    pendingPlaintextAction = nil
                }
                Button("Export Without Password", role: .destructive) {
                    exportPlaintextConfirmed = true
                    bypassPlaintextWarning = true
                    let action = pendingPlaintextAction
                    pendingPlaintextAction = nil
                    switch action {
                    case .transactions:
                        exportData()
                    case .backup:
                        exportBackup()
                    case .none:
                        break
                    }
                    bypassPlaintextWarning = false
                }
            } message: {
                Text("This export won’t be password‑protected. Other apps and services may be able to read it once shared.")
            }
            .onChange(of: isEncryptedExport) { _, newValue in
                if !newValue {
                    exportPassword = ""
                    exportPasswordConfirm = ""
                }
            }
            .onDisappear {
                exportPassword = ""
                exportPasswordConfirm = ""
                currentExportTask?.cancel()
            }
            .operationProgress(exportProgress, onCancel: cancelExport)
        }
    }

    private func cancelExport() {
        currentExportTask?.cancel()
        currentExportTask = nil
        isExporting = false
        exportProgress = nil
    }

    private var encryptedExportBinding: Binding<Bool> {
        Binding(
            get: { isEncryptedExport },
            set: { newValue in
                if newValue {
                    if !isEncryptedExport {
                        showingEncryptionWarning = true
                    }
                } else {
                    isEncryptedExport = false
                }
            }
        )
    }

    private func cleanupExportedFile() {
        guard let url = exportedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportedFileURL = nil
    }
    
    private func exportData() {
        if !isEncryptedExport, !exportPlaintextConfirmed, !bypassPlaintextWarning {
            pendingPlaintextAction = .transactions
            showingPlaintextWarning = true
            return
        }

        if isEncryptedExport {
            guard exportPassword.count >= 8 else {
                errorMessage = "Please enter a password with at least 8 characters."
                return
            }
            guard exportPassword == exportPasswordConfirm else {
                errorMessage = "Passwords don't match. Please try again."
                return
            }
        }

        isExporting = true

        let transactionsToExport = exportableTransactions
        let format = selectedFormat
        let shouldEncrypt = isEncryptedExport
        let password = exportPassword
        let totalCount = transactionsToExport.count

        currentExportTask = Task {
            await MainActor.run {
                exportProgress = OperationProgressState(
                    title: "Exporting Transactions",
                    phase: .preparing,
                    message: "Preparing \(totalCount) transactions…",
                    current: 0,
                    total: totalCount
                )
            }

            do {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                    }
                    return
                }

                await MainActor.run {
                    exportProgress?.phase = .processing
                    exportProgress?.message = shouldEncrypt ? "Encrypting data…" : "Generating CSV…"
                }

                let exporter = TransactionExporter()

                // Create temporary file with secure attributes
                let tempDir = FileManager.default.temporaryDirectory
                let fileExtension = shouldEncrypt ? "ebexport" : "csv"
                let fileName = "EscapeBudget_Transactions_\(Date().timeIntervalSince1970).\(fileExtension)"
                let fileURL = tempDir.appendingPathComponent(fileName)

                if shouldEncrypt {
                    let csvData = exporter.exportCSVData(transactionsToExport, format: format)
                    let encrypted = try EncryptedExportService.encrypt(plaintext: csvData, password: password)
                    try encrypted.write(to: fileURL, options: [.atomic])
                } else {
                    try exporter.exportTransactions(transactionsToExport, to: fileURL, format: format)
                }

                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: fileURL)
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                    }
                    return
                }

                SensitiveFileProtection.apply(to: fileURL, protection: .completeUnlessOpen)

                // Log the export
                SecurityLogger.shared.logDataExport(rowCount: transactionsToExport.count, encrypted: shouldEncrypt)

                await MainActor.run {
                    exportedFileURL = fileURL
                    isExporting = false
                    exportProgress = nil
                    showShareSheet = true

                    InAppNotificationService.post(
                        title: "Export Ready",
                        message: "\(transactionsToExport.count) transactions exported (\(format.rawValue))\(shouldEncrypt ? ", encrypted" : "").",
                        type: .success,
                        in: modelContext,
                        topic: .exportStatus
                    )
                }

            } catch {
                SecurityLogger.shared.logSecurityError(error, context: "export_data")
                await MainActor.run {
                    isExporting = false
                    exportProgress = nil
                    AppErrorCenter.shared.showOperation(.export, error: error, retryAction: exportData)

                    InAppNotificationService.post(
                        title: "Export Failed",
                        message: "Your transaction export couldn’t be created. Please try again.",
                        type: .alert,
                        in: modelContext,
                        topic: .exportStatus
                    )
                }
            }
        }
    }

    private func exportBackup() {
        if !isEncryptedExport, !exportPlaintextConfirmed, !bypassPlaintextWarning {
            pendingPlaintextAction = .backup
            showingPlaintextWarning = true
            return
        }

        if isEncryptedExport {
            guard exportPassword.count >= 8 else {
                errorMessage = "Please enter a password with at least 8 characters."
                return
            }
            guard exportPassword == exportPasswordConfirm else {
                errorMessage = "Passwords don't match. Please try again."
                return
            }
        }

        isExporting = true

        let shouldEncrypt = isEncryptedExport
        let password = exportPassword

        currentExportTask = Task {
            await MainActor.run {
                exportProgress = OperationProgressState(
                    title: "Exporting Backup",
                    phase: .preparing,
                    message: "Collecting data…"
                )
            }

            do {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                    }
                    return
                }

                let backup = try EscapeBudgetBackupService.makeBackup(modelContext: modelContext)

                await MainActor.run {
                    exportProgress?.phase = .processing
                    exportProgress?.message = shouldEncrypt ? "Encrypting backup…" : "Encoding backup…"
                }

                guard !Task.isCancelled else {
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                    }
                    return
                }

                let jsonData = try EscapeBudgetBackupService.encode(backup)
                let payload = shouldEncrypt ? try EncryptedExportService.encrypt(plaintext: jsonData, password: password) : jsonData

                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "EscapeBudget_Backup_\(Date().timeIntervalSince1970).ebbackup"
                let fileURL = tempDir.appendingPathComponent(fileName)

                try payload.write(to: fileURL, options: [.atomic])
                SensitiveFileProtection.apply(to: fileURL, protection: .completeUnlessOpen)

                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: fileURL)
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                    }
                    return
                }

                SecurityLogger.shared.logDataExport(rowCount: backup.transactions.count, encrypted: shouldEncrypt)

                await MainActor.run {
                    exportedFileURL = fileURL
                    isExporting = false
                    exportProgress = nil
                    showShareSheet = true

                    InAppNotificationService.post(
                        title: "Backup Export Ready",
                        message: "Full backup exported (\(backup.transactions.count) transactions)\(shouldEncrypt ? ", encrypted" : "").",
                        type: .success,
                        in: modelContext,
                        topic: .exportStatus
                    )
                }
            } catch {
                SecurityLogger.shared.logSecurityError(error, context: "export_backup")
                await MainActor.run {
                    isExporting = false
                    exportProgress = nil
                    AppErrorCenter.shared.showOperation(.export, error: error, retryAction: exportBackup)

                    InAppNotificationService.post(
                        title: "Backup Export Failed",
                        message: "Your backup couldn’t be created. Please try again.",
                        type: .alert,
                        in: modelContext,
                        topic: .exportStatus
                    )
                }
            }
        }
    }
}

// ShareSheet for iOS
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportDataView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
