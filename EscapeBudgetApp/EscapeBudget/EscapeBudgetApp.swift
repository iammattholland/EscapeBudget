//
//  EscapeBudgetApp.swift
//  EscapeBudget
//
//  Created by Admin on 2025-12-01.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct EscapeBudgetApp: App {
    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("shouldShowWelcome") private var shouldShowWelcome = true
    @AppStorage("sync.icloud.enabled") private var iCloudSyncEnabled = false
    @AppStorage("sync.icloud.lastAttempt") private var lastSyncAttempt: Double = 0
    @AppStorage("sync.icloud.lastSuccess") private var lastSyncSuccess: Double = 0
    @AppStorage("sync.icloud.lastError") private var lastSyncError: String = ""
    @AppStorage("userAppearance") private var userAppearanceString = "System"
    @AppStorage("appColorMode") private var appColorModeRawValue = AppColorMode.standard.rawValue
    @State private var userDataContainer: ModelContainer // Persistent storage for user data
    @State private var demoDataContainer: ModelContainer // In-memory storage for demo data
    @State private var undoRedoManager = UndoRedoManager()
    @StateObject private var errorCenter = AppErrorCenter.shared
    @StateObject private var navigator = AppNavigator()
    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var statsUpdateTask: Task<Void, Never>?
    @State private var demoSeedTask: Task<Void, Never>?
    @State private var isSwitchingDataStore = false

    /// Returns the active container based on current mode
    private var activeContainer: ModelContainer {
        isDemoMode ? demoDataContainer : userDataContainer
    }
    
    private var appearanceColorScheme: ColorScheme? {
        switch userAppearanceString {
        case "Dark":
            return .dark
        case "Light":
            return .light
        default:
            return nil
        }
    }

    private var appColorMode: AppColorMode {
        AppColorMode(rawValue: appColorModeRawValue) ?? .standard
    }

    init() {
#if canImport(UIKit)
        // Improves UX across the app by dismissing the keyboard when users scroll.
        UIScrollView.appearance().keyboardDismissMode = .onDrag
#endif
        // Create both containers at initialization
        do {
            // User data container - persistent storage
            let initialSyncEnabled = UserDefaults.standard.object(forKey: "sync.icloud.enabled") as? Bool ?? false
            let userContainer = try ModelContainerProvider.makeContainer(demoMode: false, iCloudSyncEnabled: initialSyncEnabled)
            _userDataContainer = State(initialValue: userContainer)

            // Demo data container - in-memory only (will be recreated when entering demo mode)
            let demoContainer = try ModelContainerProvider.makeContainer(demoMode: true)
            _demoDataContainer = State(initialValue: demoContainer)

            // Initialize system data for both containers
            Task { @MainActor in
                DataSeeder.ensureSystemGroups(context: userContainer.mainContext)
                DataSeeder.ensureSystemGroups(context: demoContainer.mainContext)
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if shouldShowWelcome {
                        WelcomeView(
                            onContinue: {
                                shouldShowWelcome = false
                                navigator.selectedTab = .home
                            },
                            onTryDemo: {
                                // Dismiss first to avoid any view hierarchy churn from demo mode switching.
                                shouldShowWelcome = false
                                isDemoMode = true
                                navigator.selectedTab = .home
                            }
                        )
                        .transition(.opacity)
                    } else {
                        ContentView()
                            .id(isDemoMode) // Force recreate view hierarchy when mode changes
                    }
                }
                .globalKeyboardDoneToolbar()
                .preferredColorScheme(appearanceColorScheme)
                .tint(AppColors.tint(for: appColorMode))
                .environment(\.appColorMode, appColorMode)
                .environment(\.undoRedoManager, undoRedoManager)
                .environmentObject(errorCenter)
                .environmentObject(navigator)
                .environmentObject(authService)
                    .onAppear {
                        errorCenter.setDiagnosticsModelContext(activeContainer.mainContext)
                        PremiumStatusService.shared.ensureTrialStarted()
                        UserAccountService.shared.reloadFromStorage()
                        Task { @MainActor in
                            await MonthlyAccountTotalsService.ensureUpToDateAsync(modelContext: activeContainer.mainContext)
                            await MonthlyCashflowTotalsService.ensureUpToDateAsync(modelContext: activeContainer.mainContext)
                        }
                        if !isDemoMode {
                            Task { await AutoBackupService.maybeRunWeekly(modelContext: activeContainer.mainContext) }
                        }
                    }
                .onReceive(NotificationCenter.default.publisher(for: DataChangeTracker.didChangeNotification)) { _ in
                    guard !isSwitchingDataStore else { return }
                    guard !TransactionStatsUpdateCoordinator.isDeferringUpdates else { return }

                    // Coalesce bursts of changes (e.g., demo seeding/import) into a single stats refresh.
                    statsUpdateTask?.cancel()
                    statsUpdateTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !isSwitchingDataStore else { return }
                        guard !TransactionStatsUpdateCoordinator.isDeferringUpdates else { return }

                        let dirty = TransactionStatsUpdateCoordinator.consumeDirtyState()

                        if dirty.needsFullRebuild {
                            await MonthlyAccountTotalsService.rebuildAllAsync(modelContext: activeContainer.mainContext)
                            await MonthlyCashflowTotalsService.rebuildAllAsync(modelContext: activeContainer.mainContext)
                            return
                        }

                        if !dirty.accountMonthKeys.isEmpty {
                            MonthlyAccountTotalsService.applyDirtyAccountMonthKeys(
                                modelContext: activeContainer.mainContext,
                                keys: dirty.accountMonthKeys
                            )
                        }

                        if !dirty.cashflowMonthKeys.isEmpty {
                            MonthlyCashflowTotalsService.applyDirtyMonthKeys(
                                modelContext: activeContainer.mainContext,
                                monthKeys: dirty.cashflowMonthKeys
                            )
                        }
                    }
                }

                // Lock screen overlay when authentication required
                if authService.isLocked && authService.isBiometricsEnabled {
                    LockScreenView(authService: authService)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authService.isLocked)
            .modifier(AppIconSettingsApplier())
            .alert(item: $errorCenter.presentedError) { presented in
                if let retryAction = presented.retryAction {
                    return Alert(
                        title: Text(presented.title),
                        message: Text(presented.message),
                        primaryButton: .default(Text("Retry"), action: retryAction),
                        secondaryButton: .cancel()
                    )
                } else {
                    return Alert(
                        title: Text(presented.title),
                        message: Text(presented.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
        .modelContainer(activeContainer)
        .onChange(of: isDemoMode) { _, newValue in
            // Prevent change storms (stats rebuilds / stale dirty keys) from crossing between stores.
            isSwitchingDataStore = true
            statsUpdateTask?.cancel()
            _ = TransactionStatsUpdateCoordinator.consumeDirtyState()

            if newValue {
                DemoPreferencesManager.enterDemoMode()
                recreateDemoContainer()
            } else {
                // Cancel any in-flight demo seeding work and restore real-user preferences.
                demoSeedTask?.cancel()
                DemoPreferencesManager.exitDemoMode()
            }
            errorCenter.setDiagnosticsModelContext(activeContainer.mainContext)
            // Clear undo/redo history when switching modes
            undoRedoManager.clearHistory()
            // Clear navigation state
            navigator.dismissAll()
            // Log demo mode change
            SecurityLogger.shared.logDemoModeToggle(enabled: newValue)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                isSwitchingDataStore = false
            }
        }
        .onChange(of: iCloudSyncEnabled) { _, newValue in
            guard !isDemoMode else { return }
            Task { @MainActor in
                lastSyncAttempt = Date().timeIntervalSince1970
                lastSyncError = ""
                do {
                    let container = try ModelContainerProvider.makeContainer(demoMode: false, iCloudSyncEnabled: newValue)
                    userDataContainer = container
                    DataSeeder.ensureSystemGroups(context: container.mainContext)
                    errorCenter.setDiagnosticsModelContext(container.mainContext)
                    undoRedoManager.clearHistory()
                    navigator.dismissAll()
                    lastSyncSuccess = Date().timeIntervalSince1970
                } catch {
                    // Revert toggle and surface error.
                    iCloudSyncEnabled = false
                    lastSyncError = String(describing: error)
                    errorCenter.showOperation(.sync, error: error)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                authService.appDidEnterBackground()
            case .active:
                authService.appWillEnterForeground()
                BadgeService.shared.recordAppBecameActive(modelContext: activeContainer.mainContext)
                PremiumStatusService.shared.ensureTrialStarted()
                UserAccountService.shared.reloadFromStorage()
                if !isDemoMode {
                    Task { await AutoBackupService.maybeRunWeekly(modelContext: activeContainer.mainContext) }
                    ReconcileReminderService.maybePostOverdueReconcileReminders(modelContext: activeContainer.mainContext)
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
    
    /// Ensures demo container has data
    /// This is called when entering demo mode to ensure data exists
    private func recreateDemoContainer() {
        demoSeedTask?.cancel()
        demoSeedTask = Task { @MainActor in
            TransactionStatsUpdateCoordinator.beginDeferringUpdates()
            defer { TransactionStatsUpdateCoordinator.endDeferringUpdates() }

            let context = demoDataContainer.mainContext

            // Check if demo data already exists with new category structure
            let accountDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.isDemoData })
            let existingAccounts = (try? context.fetch(accountDescriptor)) ?? []

            // Check if we have the new category groups (House, Bills & Utilities, etc.)
            let groupDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.name == "House" && $0.isDemoData })
            let houseGroups = (try? context.fetch(groupDescriptor)) ?? []
            let hasNewStructure = !houseGroups.isEmpty

            // Generate demo data if container is empty OR if it has old category structure
            if existingAccounts.isEmpty || !hasNewStructure {
                // Clear all existing demo data first
                if !existingAccounts.isEmpty {
                    clearDemoData(context: context)
                }

                // Ensure system groups without saving/bumping yet (caller will save once).
                DataSeeder.ensureSystemGroups(context: context, persistChanges: false)
                DemoDataService.generateDemoData(modelContext: context)
            } else {
                DemoDataService.ensureDemoAccountHistory(modelContext: context)
            }

            // Single post-seed refresh for cached aggregates.
            TransactionStatsUpdateCoordinator.markNeedsFullRebuild()

            context.safeSave(
                context: "EscapeBudgetApp.recreateDemoContainer",
                userMessage: "Couldn’t create demo data. Please try again.",
                showErrorToUser: true
            )
        }
    }

    /// Clears all demo data from the container.
    @MainActor
    private func clearDemoData(context: ModelContext) {
        let transactionDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.isDemoData })
        if let transactions = try? context.fetch(transactionDescriptor) {
            transactions.forEach { context.delete($0) }
        }

        let accountDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.isDemoData })
        if let accounts = try? context.fetch(accountDescriptor) {
            accounts.forEach { context.delete($0) }
        }

        let categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.isDemoData })
        if let categories = try? context.fetch(categoryDescriptor) {
            categories.forEach { context.delete($0) }
        }

        let groupDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.isDemoData })
        if let groups = try? context.fetch(groupDescriptor) {
            groups.forEach { context.delete($0) }
        }

        let tagDescriptor = FetchDescriptor<TransactionTag>(predicate: #Predicate { $0.isDemoData })
        if let tags = try? context.fetch(tagDescriptor) {
            tags.forEach { context.delete($0) }
        }

        let goalsDescriptor = FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.isDemoData })
        if let goals = try? context.fetch(goalsDescriptor) {
            goals.forEach { context.delete($0) }
        }

        let plansDescriptor = FetchDescriptor<PurchasePlan>(predicate: #Predicate { $0.isDemoData })
        if let plans = try? context.fetch(plansDescriptor) {
            plans.forEach { context.delete($0) }
        }

        let recurringDescriptor = FetchDescriptor<RecurringPurchase>(predicate: #Predicate { $0.isDemoData })
        if let recurring = try? context.fetch(recurringDescriptor) {
            recurring.forEach { context.delete($0) }
        }

        context.safeSave(context: "EscapeBudgetApp.clearDemoData", showErrorToUser: false)
    }
}

enum AppIconMode: String {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

@MainActor
enum AppIconController {
    private static let appIconModeDefaultsKey = "appIconMode"
    private static let lightIconName = "AppIconLight"
    private static let legacyLightIconName = "AppIcon-Light"

    static func migratePreferenceIfNeeded() {
        guard UserDefaults.standard.object(forKey: appIconModeDefaultsKey) == nil else { return }

        let currentAlternateIcon = UIApplication.shared.alternateIconName
        let inferredMode: AppIconMode =
            (currentAlternateIcon == lightIconName || currentAlternateIcon == legacyLightIconName) ? .light : .dark
        UserDefaults.standard.set(inferredMode.rawValue, forKey: appIconModeDefaultsKey)
    }

    static func apply(modeRawValue: String, colorScheme: ColorScheme) async {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        migratePreferenceIfNeeded()

        let mode = AppIconMode(rawValue: modeRawValue) ?? .dark
        let targetAlternateIconName: String? = {
            switch mode {
            case .dark:
                return nil
            case .light:
                return lightIconName
            case .system:
                return colorScheme == .dark ? nil : lightIconName
            }
        }()

        let currentAlternateIconName = UIApplication.shared.alternateIconName
        if currentAlternateIconName == targetAlternateIconName { return }
        if currentAlternateIconName == legacyLightIconName, targetAlternateIconName == lightIconName { return }

        do {
            try await UIApplication.shared.setAlternateIconName(targetAlternateIconName)
        } catch {
            SecurityLogger.shared.logSecurityError(error, context: "apply_app_icon")
        }
    }
}

private struct AppIconSettingsApplier: ViewModifier {
    @AppStorage("appIconMode") private var appIconModeRawValue = AppIconMode.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .task {
                await AppIconController.apply(modeRawValue: appIconModeRawValue, colorScheme: colorScheme)
            }
            .onChange(of: appIconModeRawValue) { _, newValue in
                Task {
                    await AppIconController.apply(modeRawValue: newValue, colorScheme: colorScheme)
                }
            }
            .onChange(of: colorScheme) { _, newScheme in
                guard AppIconMode(rawValue: appIconModeRawValue) == .system else { return }
                Task {
                    await AppIconController.apply(modeRawValue: appIconModeRawValue, colorScheme: newScheme)
                }
            }
    }
}
