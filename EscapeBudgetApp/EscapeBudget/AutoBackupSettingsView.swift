import SwiftUI
import SwiftData

@MainActor
struct AutoBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    @State private var isEnabled: Bool = AutoBackupService.isEnabled
    @State private var isEncrypted: Bool = AutoBackupService.isEncrypted
    @State private var keepCount: Int = AutoBackupService.keepCount
    @State private var destinationName: String? = AutoBackupService.destinationDisplayName()

    @State private var showFolderPicker = false
    @State private var isRunningBackup = false
    @State private var errorMessage: String?

    @State private var password = ""
    @State private var passwordConfirm = ""

    private var canSavePassword: Bool {
        guard isEncrypted else { return true }
        guard password.count >= 8 else { return false }
        return password == passwordConfirm
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto Backup")
                        .font(.headline)
                    Text("Automatically save a periodic full backup to a folder you choose (iCloud Drive or On My iPhone). This helps protect your data even if the app is deleted or you switch devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Destination") {
                Button {
                    showFolderPicker = true
                } label: {
                    HStack {
                        Label(destinationName == nil ? "Choose Backup Folder" : "Change Backup Folder", systemImage: "folder")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let destinationName {
                    Text(destinationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No folder selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    AutoBackupService.clearDestination()
                    destinationName = nil
                } label: {
                    Text("Clear Destination")
                }
                .disabled(destinationName == nil)
            }

            Section("Schedule") {
                Toggle("Enable Auto Backup", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        AutoBackupService.isEnabled = newValue
                    }

                Stepper("Keep last \(keepCount) backups", value: $keepCount, in: 3...52)
                    .onChange(of: keepCount) { _, newValue in
                        AutoBackupService.keepCount = newValue
                        keepCount = AutoBackupService.keepCount
                    }

                Text("When enabled, Escape Budget saves a backup weekly while the app is in use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Security") {
                Toggle("Encrypt auto-backups", isOn: $isEncrypted)
                    .onChange(of: isEncrypted) { _, newValue in
                        AutoBackupService.isEncrypted = newValue
                        if !newValue {
                            password = ""
                            passwordConfirm = ""
                            AutoBackupService.setEncryptionPassword(nil)
                        }
                    }

                if isEncrypted {
                    SecureField("Password (min 8 characters)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $passwordConfirm)
                        .textContentType(.newPassword)

                    if !password.isEmpty, password.count < 8 {
                        Text("Use at least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning(for: appColorMode))
                    } else if !passwordConfirm.isEmpty, passwordConfirm != password {
                        Text("Passwords don’t match.")
                            .font(.caption)
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                    }

                    Button("Save Password") {
                        AutoBackupService.setEncryptionPassword(password)
                    }
                    .disabled(!canSavePassword)

                    Text("Keep this password somewhere safe. It’s required to restore these backups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await runBackupNow() }
                } label: {
                    HStack {
                        Spacer()
                        if isRunningBackup {
                            ProgressView()
                        } else {
                            Text("Backup Now")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isRunningBackup || !isEnabled || destinationName == nil)
            } footer: {
                Text("You can restore these backups from Settings → Data Management → Restore Backup.")
            }
        }
        .navigationTitle("Auto Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderDocumentPicker { result in
                showFolderPicker = false
                switch result {
                case .failure:
                    errorMessage = "Unable to choose folder. Please try again."
                case .success(let url):
                    do {
                        try AutoBackupService.setDestination(url: url)
                        destinationName = AutoBackupService.destinationDisplayName()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .onAppear {
            isEnabled = AutoBackupService.isEnabled
            isEncrypted = AutoBackupService.isEncrypted
            keepCount = AutoBackupService.keepCount
            destinationName = AutoBackupService.destinationDisplayName()
            password = AutoBackupService.getEncryptionPassword() ?? ""
            passwordConfirm = password
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runBackupNow() async {
        isRunningBackup = true
        defer { isRunningBackup = false }

        do {
            try await AutoBackupService.runNow(modelContext: modelContext, reason: "manual")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        AutoBackupSettingsView()
    }
}
