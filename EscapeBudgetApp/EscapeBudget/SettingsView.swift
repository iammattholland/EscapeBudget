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
    private let topChrome: AnyView?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    @StateObject private var notificationService = NotificationService.shared
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
    @State private var showingPasscodeSetup = false
    @State private var passcodeStage: PasscodeSetupStage = .create
    @State private var passcodeDraft = ""
    @State private var passcodeError = false
    @State private var passcodeErrorMessage = "Passcodes didn't match. Try again."
    @State private var passcodeResetKey = 0
    @State private var appearanceMode: String = "System"
    @State private var showingNotificationOptions = false
    @State private var hasInitializedServices = false

    private enum PasscodeSetupStage {
        case verifyCurrent
        case create
        case confirm
    }
    
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
    
    init(embedded: Bool = false, showsAppLogo: Bool = true, topChrome: (() -> AnyView)? = nil) {
        self.embedded = embedded
        self.showsAppLogo = showsAppLogo
        self.topChrome = topChrome?()
    }

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

    private var settingsList: some View {
        settingsListView
    }

    private var settingsBaseList: some View {
        List {
            if topChrome != nil {
                AppChromeListRow(topChrome: topChrome, scrollID: "SettingsView.scroll")
            }
            demoModeActiveSection
            accountSection
            planSection
            preferencesSection
            appearanceSection
            notificationsSection
            privacySecuritySection
            dataManagementSection
            demoModeToggleSection
            aboutSection
        }
    }

    private var settingsListView: some View {
        settingsBaseList
            .appListCompactSpacing()
            .environment(\.symbolRenderingMode, .monochrome)
            .tint(.primary)
            .appConstrainContentWidth()
            .background(ScrollOffsetEmitter(id: "SettingsView.scroll"))
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
            .sheet(isPresented: $showingPasscodeSetup, onDismiss: {
                if !authService.isPasscodeEnabled {
                    passcodeStage = .create
                    passcodeDraft = ""
                    passcodeError = false
                    passcodeErrorMessage = "Passcodes didn't match. Try again."
                    passcodeResetKey += 1
                }
            }) {
                NavigationStack {
                    passcodeSetupSheet
                        .navigationTitle("Passcode")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    passcodeStage = .create
                                    passcodeDraft = ""
                                    passcodeError = false
                                    passcodeErrorMessage = "Passcodes didn't match. Try again."
                                    passcodeResetKey += 1
                                    showingPasscodeSetup = false
                                }
                            }
                        }
                }
            }
            .onAppear {
                appearanceMode = settings.userAppearance

                guard !hasInitializedServices else { return }
                hasInitializedServices = true

                premiumStatusService.ensureTrialStarted()
                userAccountService.reloadFromStorage()
            }
    }

    @ViewBuilder
    private var demoModeActiveSection: some View {
        if settings.isDemoMode {
            Section {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
                    HStack(spacing: AppDesign.Theme.Spacing.compact) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Demo Mode Active")
                            .appSectionTitleText()
                        Spacer()
                        Button("Turn Off") {
                            settings.isDemoMode = false
                        }
                        .appSecondaryCTA()
                        .controlSize(.small)
                    }

                    Text("You're viewing sample data. Your real data is safe and will return when you turn off demo mode.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    Button {
                        resetDemoData()
                    } label: {
                        Label("Reset Demo Data", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)
            } header: {
                Text("Demo")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if userAccountService.isSignedIn {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
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
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                    Text("Sign in to help protect your access to premium features and make future upgrades like restore + multi-device support possible.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        userAccountService.handleSignInCompletion(result: result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)
            }
        }
    }

    private var planSection: some View {
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
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(true)
        }
    }

    private var preferencesSection: some View {
        @Bindable var settings = settings
        return Section("Preferences") {
            Picker(selection: $settings.appLanguage) {
                ForEach(languages, id: \.self) { language in
                    Text(language).tag(language)
                }
            } label: {
                Label {
                    Text("Language")
                } icon: {
                    Image(systemName: "globe")
                        .foregroundStyle(.primary)
                }
            }

            NavigationLink {
                CurrencySelectionView(selectedCurrency: $settings.currencyCode, currencies: currencies)
            } label: {
                HStack {
                    Label {
                        Text("Currency")
                            .fontWeight(.regular)
                    } icon: {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if let currency = currencies.first(where: { $0.0 == settings.currencyCode }) {
                        Text(currency.0)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var appearanceSection: some View {
        @Bindable var settings = settings
        return Section("Appearance") {
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                HStack {
                    Image(systemName: "moon")
                        .foregroundStyle(.primary)
                        .frame(width: 20)
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
                }
            }

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                HStack {
                    Image(systemName: "app")
                        .foregroundStyle(.primary)
                        .frame(width: 20)
                    Picker("App Icon", selection: Binding(
                        get: { settings.appIconModeRawValue },
                        set: { newValue in
                            settings.appIconModeRawValue = newValue
                            Task {
                                await AppIconController.apply(modeRawValue: newValue)
                            }
                        }
                    )) {
                        Text("System").tag(AppIconMode.system.rawValue)
                        Text("Dark").tag("Dark")
                        Text("Light").tag("Light")
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                HStack {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(.primary)
                        .frame(width: 20)
                    Picker("App Colours", selection: $settings.appColorModeRawValue) {
                        ForEach(AppColorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        @Bindable var settings = settings
        return Section("Notifications") {
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                HStack {
                    Label {
                        Text("System Notifications")
                            .fontWeight(.regular)
                    } icon: {
                        Image(systemName: "bell")
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Text(notificationService.notificationsEnabled ? "Enabled" : "Off")
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup(
                isExpanded: $showingNotificationOptions,
                content: {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Show details in iOS notifications", isOn: $settings.showSensitiveNotificationContent)
                            Text("When off, notifications hide amounts, filenames, and other details on your lock screen.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: settings.showSensitiveNotificationContent) { _, _ in
                            Task {
                                if notificationService.notificationsEnabled, settings.billReminders {
                                    await notificationService.scheduleAllRecurringBillNotifications(
                                        modelContext: modelContext,
                                        daysBefore: notificationService.reminderDaysBefore
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Budget Alerts", isOn: $settings.budgetAlerts)
                            Text("Get notified when approaching budget limits")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Bill Reminders", isOn: $settings.billReminders)
                            Text("Receive reminders for upcoming recurring bills")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Transfers Inbox", isOn: $settings.transfersInboxNotifications)
                            Text("Get notified when transfers need review")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Import Complete", isOn: $settings.importCompleteNotifications)
                            Text("Get notified when data imports finish")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Export Status", isOn: $settings.exportStatusNotifications)
                            Text("Get notified when exports are ready or fail")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Backup & Restore", isOn: $settings.backupRestoreNotifications)
                            Text("Get notified when backups restore successfully or fail")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Rule Applied", isOn: $settings.ruleAppliedNotifications)
                            Text("Get notified when retroactive rules complete")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Toggle("Badge Achievements", isOn: $settings.badgeAchievementNotifications)
                            Text("Get notified when you earn a badge")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, AppDesign.Theme.Spacing.compact)
                },
                label: {
                    Label {
                        Text("Notification Options")
                            .fontWeight(.regular)
                    } icon: {
                        Image(systemName: "bell.badge")
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var demoModeToggleSection: some View {
        if !settings.isDemoMode {
            @Bindable var settings = settings
            Section("Demo") {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
                    Toggle(isOn: $settings.isDemoMode) {
                        Label("Try Demo Mode", systemImage: "sparkles")
                    }
                    Text("Explore with sample data without affecting your real information")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)
            }
        }
    }

    @ViewBuilder
    private var privacySecuritySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { authService.isPasscodeEnabled },
                set: { newValue in
                    if newValue {
                        passcodeStage = .create
                        passcodeDraft = ""
                        passcodeError = false
                        passcodeErrorMessage = "Passcodes didn't match. Try again."
                        passcodeResetKey += 1
                        showingPasscodeSetup = true
                    } else {
                        authService.disablePasscode()
                    }
                }
            )) {
                Label("Passcode Lock", systemImage: "number.circle")
            }
            .tint(AppDesign.Colors.tint(for: appColorMode))

            if authService.isPasscodeEnabled {
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
                .tint(AppDesign.Colors.tint(for: appColorMode))

                Button {
                    passcodeStage = .verifyCurrent
                    passcodeDraft = ""
                    passcodeError = false
                    passcodeErrorMessage = "Current passcode is incorrect. Try again."
                    passcodeResetKey += 1
                    showingPasscodeSetup = true
                } label: {
                    HStack {
                        Text("Change Passcode")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Privacy & Security")
        } footer: {
            if authService.biometricType == .none {
                Text("Biometric authentication is not available on this device")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dataManagementSection: some View {
        Section("Data Management") {
            NavigationLink {
                DataHealthView()
            } label: {
                HStack {
                    Label("Data Health", systemImage: "heart.text.square")
                    Spacer()
                    Text(settings.iCloudSyncEnabled ? "iCloud Sync On" : "Local")
                        .appCaptionText()
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
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button(action: { showingImportData = true }) {
                HStack {
                    Label("Import Data", systemImage: "square.and.arrow.down")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            NavigationLink {
                AutoBackupSettingsView()
            } label: {
                HStack {
                    HStack(spacing: AppDesign.Theme.Spacing.compact) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                        Text("Auto Backup")
                            .fontWeight(.regular)
                    }
                    Spacer()
                    Text(AutoBackupService.destinationDisplayName() ?? "Off")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button(action: { showingRestoreBackup = true }) {
                HStack {
                    Label("Restore Backup", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

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
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary)
            .disabled(isRebuildingStats)

            Button(action: { showingDeleteSheet = true }) {
                HStack {
                    HStack(spacing: AppDesign.Theme.Spacing.compact) {
                        Image(systemName: "trash")
                            .foregroundStyle(.primary)
                        Text("Delete All Data")
                            .fontWeight(.regular)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text("2025.12.05")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deleteSheet: some View {
        NavigationStack {
            Form {
                Section("Before You Delete") {
                    Text("Export your data first if you may need it later. Deleting cannot be undone.")
                        .appFootnoteText()
                        .foregroundStyle(.secondary)
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
                        .appFootnoteText()
                        .foregroundStyle(.secondary)
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
        settings.userAppearance = mode

        // Force-update all windows immediately so the change is visible without leaving Settings.
        let style: UIUserInterfaceStyle = mode == "Dark" ? .dark : (mode == "Light" ? .light : .unspecified)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
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

    private var passcodeSetupSheet: some View {
        PasscodeEntryView(
            title: {
                switch passcodeStage {
                case .verifyCurrent:
                    return "Current Passcode"
                case .create:
                    return "Create Passcode"
                case .confirm:
                    return "Confirm Passcode"
                }
            }(),
            subtitle: {
                switch passcodeStage {
                case .verifyCurrent:
                    return "Enter your current passcode to continue"
                case .create:
                    return "Choose a 4-digit passcode"
                case .confirm:
                    return "Re-enter your passcode"
                }
            }(),
            showsBiometricButton: false,
            biometricTitle: "",
            resetKey: passcodeResetKey,
            onBiometricTap: {},
            onComplete: { code in
                switch passcodeStage {
                case .verifyCurrent:
                    if authService.verifyAppPasscode(code) {
                        passcodeStage = .create
                        passcodeDraft = ""
                        passcodeError = false
                        passcodeErrorMessage = "Passcodes didn't match. Try again."
                        passcodeResetKey += 1
                    } else {
                        passcodeErrorMessage = "Current passcode is incorrect. Try again."
                        passcodeError = true
                        passcodeResetKey += 1
                    }
                case .create:
                    passcodeDraft = code
                    passcodeStage = .confirm
                    passcodeError = false
                    passcodeResetKey += 1
                case .confirm:
                    if code == passcodeDraft {
                        if authService.setPasscode(code) {
                            showingPasscodeSetup = false
                        } else {
                            passcodeErrorMessage = "Passcode couldn't be saved."
                            passcodeError = true
                        }
                    } else {
                        passcodeErrorMessage = "Passcodes didn't match. Try again."
                        passcodeError = true
                        passcodeDraft = ""
                        passcodeStage = .create
                        passcodeResetKey += 1
                    }
                }
            },
            showError: $passcodeError,
            errorMessage: passcodeErrorMessage
        )
        .padding(.horizontal, AppDesign.Theme.Spacing.xxLarge)
    }
    
    @MainActor
    private func resetDemoData() {
        guard settings.isDemoMode else { return }

        // Toggle demo mode off and back on to trigger fresh demo data generation
        settings.isDemoMode = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settings.isDemoMode = true
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
            settings.shouldShowWelcome = true
            settings.isDemoMode = false

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
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Text(currency.2)
                                .foregroundStyle(.primary)
                            Text("\(currency.0) • \(currency.1)")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedCurrency == currency.0 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
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
