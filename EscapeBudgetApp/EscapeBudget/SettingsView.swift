import SwiftUI
import SwiftData
import LocalAuthentication
import AuthenticationServices
import UserNotifications
import UIKit

@MainActor
struct SettingsView: View {
    var embedded: Bool = false
    var showsAppLogo: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("userAppearance") private var userAppearanceString = "System"
    @AppStorage("appIconMode") private var appIconModeRawValue = AppIconMode.dark.rawValue
    @AppStorage("appColorMode") private var appColorModeRawValue = AppColorMode.standard.rawValue
    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("shouldShowWelcome") private var shouldShowWelcome = true
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("appLanguage") private var appLanguage = "English"
    @AppStorage("weekStartDay") private var weekStartDay = "Sunday"
    @AppStorage("sync.icloud.enabled") private var iCloudSyncEnabled = false
	@AppStorage("budgetAlerts") private var budgetAlerts = true
	@AppStorage("billReminders") private var billReminders = true
	@AppStorage("notifications.transfersInbox") private var transfersInboxNotifications = true
	@AppStorage("notifications.importComplete") private var importCompleteNotifications = true
	@AppStorage("notifications.exportStatus") private var exportStatusNotifications = true
	@AppStorage("notifications.backupRestore") private var backupRestoreNotifications = true
	@AppStorage("notifications.ruleApplied") private var ruleAppliedNotifications = true
	@AppStorage("notifications.badges") private var badgeAchievementNotifications = true
    @AppStorage("notifications.showSensitiveContent") private var showSensitiveNotificationContent = false

    @ObservedObject private var notificationService = NotificationService.shared
    @StateObject private var userAccountService = UserAccountService.shared
    @StateObject private var premiumStatusService = PremiumStatusService.shared

    @State private var showingDeleteSheet = false
    @State private var deleteConfirmationText = ""
    @State private var showingExportData = false
    @State private var showingImportData = false
    @State private var showingRestoreBackup = false
    @State private var showingRebuildStatsConfirm = false
    @State private var isRebuildingStats = false
    @State private var isEnablingBiometrics = false
    @State private var showBiometricError = false
    @State private var appearanceMode: String = "System"
    @State private var showingNotificationOptions = false
    @State private var hasInitializedServices = false
    
    // Currency options
    let currencies = [
        ("USD", "$", "US Dollar"),
        ("CAD", "CA$", "Canadian Dollar"),
        ("EUR", "€", "Euro"),
        ("GBP", "£", "British Pound"),
        ("JPY", "¥", "Japanese Yen"),
        ("CNY", "¥", "Chinese Yuan"),
        ("INR", "₹", "Indian Rupee"),
        ("AUD", "A$", "Australian Dollar"),
        ("CHF", "CHF", "Swiss Franc"),
        ("MXN", "MX$", "Mexican Peso"),
        ("BRL", "R$", "Brazilian Real"),
        ("RUB", "₽", "Russian Ruble"),
        ("KRW", "₩", "South Korean Won"),
        ("SGD", "S$", "Singapore Dollar"),
        ("HKD", "HK$", "Hong Kong Dollar"),
        ("NZD", "NZ$", "New Zealand Dollar"),
        ("SEK", "kr", "Swedish Krona"),
        ("NOK", "kr", "Norwegian Krone"),
        ("DKK", "kr", "Danish Krone"),
        ("PLN", "zł", "Polish Zloty"),
        ("THB", "฿", "Thai Baht"),
        ("IDR", "Rp", "Indonesian Rupiah"),
        ("MYR", "RM", "Malaysian Ringgit"),
        ("PHP", "₱", "Philippine Peso"),
        ("ZAR", "R", "South African Rand"),
        ("TRY", "₺", "Turkish Lira"),
        ("AED", "د.إ", "UAE Dirham"),
        ("SAR", "﷼", "Saudi Riyal"),
        ("ILS", "₪", "Israeli Shekel"),
        ("CZK", "Kč", "Czech Koruna"),
        ("HUF", "Ft", "Hungarian Forint"),
        ("RON", "lei", "Romanian Leu"),
        ("BGN", "лв", "Bulgarian Lev"),
        ("HRK", "kn", "Croatian Kuna"),
        ("VND", "₫", "Vietnamese Dong"),
        ("EGP", "E£", "Egyptian Pound"),
        ("NGN", "₦", "Nigerian Naira"),
        ("KES", "KSh", "Kenyan Shilling"),
        ("PKR", "₨", "Pakistani Rupee"),
        ("BDT", "৳", "Bangladeshi Taka"),
        ("LKR", "Rs", "Sri Lankan Rupee"),
        ("ARS", "AR$", "Argentine Peso"),
        ("CLP", "CL$", "Chilean Peso"),
        ("COP", "CO$", "Colombian Peso"),
        ("PEN", "S/", "Peruvian Sol"),
        ("UAH", "₴", "Ukrainian Hryvnia")
    ]
    
    let weekDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    let languages = ["English"]
    
    var body: some View {
        Group {
            if embedded {
                settingsList
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    settingsList
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .modifier(AppLogoVisibilityModifier(isVisible: showsAppLogo))
                }
            }
        }
    }

    @ViewBuilder
    private var settingsList: some View {
        List {
            ScrollOffsetReader(coordinateSpace: "SettingsView.scroll", id: "SettingsView.scroll")
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Demo Mode Section - Prominent at top
            if isDemoMode {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Demo Mode Active")
                                .font(.headline)
                            Spacer()
                            Button("Turn Off") {
                                isDemoMode = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("You're viewing sample data. Your real data is safe and will return when you turn off demo mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            resetDemoData()
                        } label: {
                            Label("Reset Demo Data", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Demo")
                }
            }

            Section("Account") {
                if userAccountService.isSignedIn {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Signed in with Apple", systemImage: "person.crop.circle.fill")
                            Spacer()
                            Text(userAccountService.credentialState == .authorized ? "Active" : "Check")
                                .foregroundStyle(.secondary)
                        }

                        if let email = userAccountService.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        } else {
                            LabeledContent("Email", value: "Hidden by Apple")
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            userAccountService.signOut()
                        } label: {
                            Text("Sign Out")
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sign in to help protect your access to premium features and make future upgrades like restore + multi-device support possible.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.email]
                        } onCompletion: { result in
                            userAccountService.handleSignInCompletion(result: result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 44)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Plan") {
                switch premiumStatusService.plan {
                case .premium:
                    LabeledContent("Status", value: "Premium Active")
                case .trial(let daysRemaining):
                    LabeledContent("Status", value: "Trial • \(daysRemaining) days left")
                case .free:
                    LabeledContent("Status", value: "Free • Trial ended")
                }

                Button {
                    // Placeholder for StoreKit paywall + restore purchases.
                } label: {
                    HStack {
                        Label("Upgrade to Premium", systemImage: "crown")
                        Spacer()
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(true)
            }

            Section("Preferences") {
                Picker("Language", selection: $appLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                    }

                    NavigationLink {
                        CurrencySelectionView(selectedCurrency: $currencyCode, currencies: currencies)
                    } label: {
                        HStack {
                            Text("Currency")
                            Spacer()
                            if let currency = currencies.first(where: { $0.0 == currencyCode }) {
                                Text(currency.0)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                
                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("App Theme", selection: Binding(
                            get: { appearanceMode },
                            set: { newValue in
                                appearanceMode = newValue
                                updateAppearance(newValue)
                            }
                        )) {
                            Text("System").tag("System")
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                        }
                        Text("Choose whether the app follows your system appearance or stays in light/dark mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker("App Icon", selection: Binding(
                            get: { appIconModeRawValue },
                            set: { newValue in
                                appIconModeRawValue = newValue
                                Task {
                                    await AppIconController.apply(modeRawValue: newValue, colorScheme: colorScheme)
                                }
                            }
                        )) {
                            Text("System").tag(AppIconMode.system.rawValue)
                            Text("Dark").tag("Dark")
                            Text("Light").tag("Light")
                        }
                        Text("Choose whether the icon follows your appearance or stays light/dark.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker("App Colours", selection: $appColorModeRawValue) {
                            ForEach(AppColorMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        Text("Choose the color scheme for the app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Notifications") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("System Notifications")
                            Spacer()
                            Text(notificationService.notificationsEnabled ? "Enabled" : "Off")
                                .foregroundStyle(.secondary)
                        }
                        Button("Enable System Notifications") {
                            Task {
                                _ = await notificationService.requestAuthorization()
                                if notificationService.notificationsEnabled, billReminders {
                                    await notificationService.scheduleAllRecurringBillNotifications(
                                        modelContext: modelContext,
                                        daysBefore: notificationService.reminderDaysBefore
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderless)

                        Text("iOS notifications require permission. In-app notifications always appear in your Notifications feed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    DisclosureGroup("Notification Options", isExpanded: $showingNotificationOptions) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Show details in iOS notifications", isOn: $showSensitiveNotificationContent)
                                Text("When off, notifications hide amounts, filenames, and other details on your lock screen.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .onChange(of: showSensitiveNotificationContent) { _, _ in
                                Task {
                                    if notificationService.notificationsEnabled, billReminders {
                                        await notificationService.scheduleAllRecurringBillNotifications(
                                            modelContext: modelContext,
                                            daysBefore: notificationService.reminderDaysBefore
                                        )
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Budget Alerts", isOn: $budgetAlerts)
                                Text("Get notified when approaching budget limits")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Bill Reminders", isOn: $billReminders)
                                Text("Receive reminders for upcoming recurring bills")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Transfers Inbox", isOn: $transfersInboxNotifications)
                                Text("Get notified when transfers need review")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Import Complete", isOn: $importCompleteNotifications)
                                Text("Get notified when data imports finish")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Export Status", isOn: $exportStatusNotifications)
                                Text("Get notified when exports are ready or fail")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Backup & Restore", isOn: $backupRestoreNotifications)
                                Text("Get notified when backups restore successfully or fail")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Rule Applied", isOn: $ruleAppliedNotifications)
                                Text("Get notified when retroactive rules complete")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Badge Achievements", isOn: $badgeAchievementNotifications)
                                Text("Get notified when you earn a badge")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                // Demo Mode Toggle when NOT in demo mode
                if !isDemoMode {
                    Section("Demo") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Try Demo Mode")
                                        .font(.headline)
                                    Text("Explore with sample data without affecting your real information")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                isDemoMode = true
                            } label: {
                                HStack {
                                    Text("Enable Demo Mode")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Privacy & Security") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { authService.isBiometricsEnabled },
                            set: { newValue in
                                if newValue {
                                    enableBiometrics()
                                } else {
                                    authService.disableBiometrics()
                                }
                            }
                        )) {
                            HStack {
                                Label("\(authService.biometricType.displayName) Lock", systemImage: authService.biometricType.systemImage)
                                if isEnablingBiometrics {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isEnablingBiometrics || authService.biometricType == .none)

                        if authService.biometricType == .none {
                            Text("Biometric authentication is not available on this device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Require \(authService.biometricType.displayName) to unlock the app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Data Management") {
                    NavigationLink {
                        DataHealthView()
                    } label: {
                        HStack {
                            Label("Data Health", systemImage: "heart.text.square")
                            Spacer()
                            Text(iCloudSyncEnabled ? "iCloud Sync On" : "Local")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SavedReceiptsView()
                    } label: {
                        Label("Saved Receipts", systemImage: "doc.text.image")
                    }

                    Button(action: { showingExportData = true }) {
                        HStack {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: { showingImportData = true }) {
                        HStack {
                            Label("Import Data", systemImage: "square.and.arrow.down")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    NavigationLink {
                        AutoBackupSettingsView()
                    } label: {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.primary)
                                Text("Auto Backup")
                            }
                            Spacer()
                            Text(AutoBackupService.destinationDisplayName() ?? "Off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button(action: { showingRestoreBackup = true }) {
                        HStack {
                            Label("Restore Backup", systemImage: "arrow.counterclockwise")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        showingRebuildStatsConfirm = true
                    } label: {
                        HStack {
                            Label("Rebuild Stats", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isRebuildingStats {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .disabled(isRebuildingStats)

                    Button(action: { showingDeleteSheet = true }) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.primary)
                                Text("Delete All Data")
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2025.12.05")
                            .foregroundColor(.secondary)
                    }
                }
        }
        .coordinateSpace(name: "SettingsView.scroll")
        .alert("Authentication Failed", isPresented: $showBiometricError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not enable \(authService.biometricType.displayName). Please try again or check your device settings.")
        }
        .sheet(isPresented: $showingExportData) {
            ExportDataView()
        }
        .sheet(isPresented: $showingImportData) {
            ImportDataView()
        }
        .sheet(isPresented: $showingRestoreBackup) {
            RestoreBackupView()
        }
        .confirmationDialog("Rebuild Stats?", isPresented: $showingRebuildStatsConfirm, titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) {
                Task { @MainActor in
                    isRebuildingStats = true
                    TransactionStatsUpdateCoordinator.beginDeferringUpdates()
                    defer {
                        TransactionStatsUpdateCoordinator.endDeferringUpdates()
                        isRebuildingStats = false
                    }

                    MonthlyAccountTotalsService.rebuildAll(modelContext: modelContext)
                    MonthlyCashflowTotalsService.rebuildAll(modelContext: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rebuilds aggregated totals used for Home/Review/Forecast/Retirement. Use if numbers ever look off after a big import.")
        }
        .sheet(isPresented: $showingDeleteSheet) {
            deleteSheet
        }
        .onAppear {
            appearanceMode = userAppearanceString

            guard !hasInitializedServices else { return }
            hasInitializedServices = true

            premiumStatusService.ensureTrialStarted()
            userAccountService.reloadFromStorage()
        }
    }

    private var deleteSheet: some View {
        NavigationStack {
            Form {
                Section("Before You Delete") {
                    Text("Export your data first if you may need it later. Deleting cannot be undone.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button {
                        showingDeleteSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingExportData = true
                        }
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                }
                
                Section("Confirmation") {
                    Text("Type DELETE to confirm.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("Type DELETE", text: $deleteConfirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: deleteConfirmationText) { _, newValue in
                            deleteConfirmationText = newValue.uppercased()
                        }
                }
                
                Section {
                    Button("Delete All Data", role: .destructive) {
                        deleteAllData()
                        deleteConfirmationText = ""
                        showingDeleteSheet = false
                    }
                    .disabled(deleteConfirmationText != "DELETE")
                }
            }
            .navigationTitle("Delete All Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        deleteConfirmationText = ""
                        showingDeleteSheet = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .solidPresentationBackground()
    }
    
    private func updateAppearance(_ mode: String) {
        userAppearanceString = mode
        
        // This force updates the window appearance immediately
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.first?.overrideUserInterfaceStyle = mode == "Dark" ? .dark : (mode == "Light" ? .light : .unspecified)
        }
    }
    
    private func enableBiometrics() {
        isEnablingBiometrics = true
        Task {
            let success = await authService.enableBiometrics()
            await MainActor.run {
                isEnablingBiometrics = false
                if !success {
                    showBiometricError = true
                }
            }
        }
    }
    
    @MainActor
    private func resetDemoData() {
        guard isDemoMode else { return }

        // Toggle demo mode off and back on to trigger fresh demo data generation
        isDemoMode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isDemoMode = true
        }
    }

    @MainActor
    private func deleteAllData() {
        do {
            // Delete all entities in dependency order
            try modelContext.delete(model: AutoRuleApplication.self)
            try modelContext.delete(model: AutoRule.self)
            try modelContext.delete(model: TransactionHistoryEntry.self)
            try modelContext.delete(model: ReceiptImage.self)
            try modelContext.delete(model: Transaction.self)
            try modelContext.delete(model: TransactionTag.self)
            try modelContext.delete(model: Category.self)
            try modelContext.delete(model: CategoryGroup.self)
            try modelContext.delete(model: Account.self)
            try modelContext.delete(model: MonthlyAccountTotal.self)
            try modelContext.delete(model: MonthlyCashflowTotal.self)
            try modelContext.delete(model: SavingsGoal.self)
            try modelContext.delete(model: PurchasePlan.self)
            try modelContext.delete(model: RecurringPurchase.self)
            try modelContext.delete(model: TransferPattern.self)
            try modelContext.delete(model: CategoryPattern.self)
            try modelContext.delete(model: PayeePattern.self)
            try modelContext.delete(model: RecurringPattern.self)
            try modelContext.delete(model: BudgetForecast.self)
            try modelContext.delete(model: DiagnosticEvent.self)
            try modelContext.delete(model: AppNotification.self)
            try modelContext.delete(model: CustomDashboardWidget.self)

            // Save the deletions
            try modelContext.save()
            DataChangeTracker.bump()

            // Log the deletion
            SecurityLogger.shared.logDataDeletion(entityType: "all", count: -1)

            // Recreate system groups (Income)
            DataSeeder.ensureSystemGroups(context: modelContext)

            // Reset notification badge
            UserDefaults.standard.set(false, forKey: "hasNotifications")

            // Clear local notifications + delivered notifications.
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            if #available(iOS 17.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }

            // Clear all keychain-held secrets and account state (e.g. backup password, sign-in token).
            KeychainService.shared.removeAll()

            // Reset app preferences + local temp + diagnostics/log files.
            LocalDataWipeService.wipeUserDefaults()
            LocalDataWipeService.wipeLocalFiles()
            SecurityLogger.shared.resetAuditLog()

            // Reset badges / streaks
            BadgeService.shared.resetAll()

            // Show startup flow again
            shouldShowWelcome = true
            isDemoMode = false

            // Ensure the user lands on Home after the welcome flow.
            navigator.selectedTab = .home
            navigator.manageNavigator.selectedSection = .transactions

            deleteConfirmationText = ""
            showingDeleteSheet = false
            if embedded {
                dismiss()
            }
        } catch {
            SecurityLogger.shared.logSecurityError(error, context: "delete_all_data")
        }
    }
}

private struct AppLogoVisibilityModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        if isVisible {
            content.withAppLogo()
        } else {
            content
        }
    }
}

struct CurrencySelectionView: View {
    @Binding var selectedCurrency: String
    let currencies: [(String, String, String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(currencies, id: \.0) { currency in
                Button {
                    selectedCurrency = currency.0
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currency.2)
                                .foregroundColor(.primary)
                            Text("\(currency.0) • \(currency.1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedCurrency == currency.0 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService.shared)
}
