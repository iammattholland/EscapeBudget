import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct RestoreBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    @State private var showPicker = false
    @State private var backupURL: URL?
    @State private var backup: EscapeBudgetBackup?

    @State private var isReadingFile = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    @State private var pendingEncryptedData: Data?
    @State private var password = ""
    @State private var showingPasswordSheet = false

    @State private var showingRestoreConfirm = false
    @State private var showingRestoreComplete = false

    private let encryptedMagic = Data([0x4D, 0x4D, 0x45, 0x31]) // "MME1"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Restore an Escape Budget backup")
                            .appSectionTitleText()
                        Text("This replaces your current data with what’s in the backup file.")
                            .appSecondaryBodyText()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xSmall)
                }

                Section("Backup File") {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Label(backupURL == nil ? "Choose Backup File" : "Choose Another File", systemImage: "doc")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isReadingFile || isRestoring)

                    if let backupURL {
                        Text(backupURL.lastPathComponent)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }

                    if isReadingFile {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ProgressView()
                            Text("Reading backup…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let backup {
                    Section("Summary") {
                        LabeledContent("Exported", value: backup.exportedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Accounts", value: "\(backup.accounts.count)")
                        LabeledContent("Transactions", value: "\(backup.transactions.count)")
                        LabeledContent("Budget Categories", value: "\(backup.categories.count)")
                        LabeledContent("Tags", value: "\(backup.tags.count)")
                        LabeledContent("Savings Goals", value: "\(backup.savingsGoals.count)")
                    }

                    Section {
                        Button(role: .destructive) {
                            showingRestoreConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(isRestoring ? "Restoring…" : "Restore Backup")
                                    .appSectionTitleText()
                                Spacer()
                            }
                        }
                        .disabled(isRestoring)
                    } footer: {
                        Text("Restoring deletes your current data first. This cannot be undone.")
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .sheet(isPresented: $showPicker) {
                BackupDocumentPicker { result in
                    handlePickedFile(result)
                }
            }
            .sheet(isPresented: $showingPasswordSheet) {
                NavigationStack {
                    Form {
                        Section("Password") {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }
                    }
                    .navigationTitle("Encrypted Backup")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                password = ""
                                pendingEncryptedData = nil
                                showingPasswordSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Unlock") {
                                Task { await unlockEncryptedBackup() }
                            }
                            .disabled(password.isEmpty)
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: $showingRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    Task { await restoreBackup() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete all current data and replace it with the backup contents.")
            }
            .alert("Restore Complete", isPresented: $showingRestoreComplete) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your data has been restored.")
            }
        }
    }

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        showPicker = false
        backup = nil
        pendingEncryptedData = nil
        password = ""

        switch result {
        case .failure:
            errorMessage = "Unable to select file. Please try again."
        case .success(let urls):
            guard let url = urls.first else { return }
            readBackup(from: url)
        }
    }

    private func readBackup(from url: URL) {
        isReadingFile = true
        let gotAccess = url.startAccessingSecurityScopedResource()

        let tempDir = FileManager.default.temporaryDirectory
        let dstURL = tempDir.appendingPathComponent(UUID().uuidString + ".ebbackup")

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                // Validate before copying (size/type).
                try SensitiveFileProtection.validateImportableFile(
                    at: url,
                    maxBytes: 50 * 1024 * 1024,
                    allowedExtensions: ["ebbackup", "mmbackup"]
                )

                try FileManager.default.copyItem(at: url, to: dstURL)

                SensitiveFileProtection.apply(to: dstURL, protection: .completeUnlessOpen)

                let data = try Data(contentsOf: dstURL, options: [.mappedIfSafe])
                try? FileManager.default.removeItem(at: dstURL)

                DispatchQueue.main.async {
                    self.backupURL = url
                    self.isReadingFile = false
                    if data.starts(with: self.encryptedMagic) {
                        self.pendingEncryptedData = data
                        self.showingPasswordSheet = true
                    } else {
                        do {
                            self.backup = try EscapeBudgetBackupService.decode(data)
                        } catch {
                            self.errorMessage = "That file doesn’t look like a valid Escape Budget backup."
                        }
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: dstURL)
                DispatchQueue.main.async {
                    self.isReadingFile = false
                    if (error as? SensitiveFileProtection.ValidationError) != nil {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = "Unable to read the selected file."
                    }
                }
            }
        }
    }

    @MainActor
    private func unlockEncryptedBackup() async {
        guard let ciphertext = pendingEncryptedData else { return }
        do {
            let plaintext = try EncryptedExportService.decrypt(ciphertext: ciphertext, password: password)
            backup = try EscapeBudgetBackupService.decode(plaintext)
            pendingEncryptedData = nil
            password = ""
            showingPasswordSheet = false
        } catch {
            errorMessage = "Incorrect password or invalid backup file."
        }
    }

    @MainActor
    private func restoreBackup() async {
        guard let backup else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try EscapeBudgetBackupService.restore(backup, modelContext: modelContext)
            SecurityLogger.shared.logDataImport(rowCount: backup.transactions.count, source: "ebbackup")
            InAppNotificationService.post(
                title: "Backup Restored",
                message: "Restored \(backup.transactions.count) transactions from your backup.",
                type: .success,
                in: modelContext,
                topic: .backupRestore
            )
            showingRestoreComplete = true
        } catch {
            errorMessage = "Restore failed. Please try again."
            InAppNotificationService.post(
                title: "Restore Failed",
                message: "Your backup couldn’t be restored. Please try again.",
                type: .alert,
                in: modelContext,
                topic: .backupRestore
            )
        }
    }
}

private struct BackupDocumentPicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.escapeBudgetBackup, .data],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(.success([]))
        }
    }
}

#Preview {
    RestoreBackupView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
