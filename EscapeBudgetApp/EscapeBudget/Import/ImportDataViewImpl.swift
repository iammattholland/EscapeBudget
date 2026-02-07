import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
struct ImportDataViewImpl: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigator: AppNavigator
                                    @Environment(\.appColorMode) var appColorMode
                                    @Environment(\.appSettings) var settings
    @Query(sort: \Account.name) var accounts: [Account]

    let initialAccount: Account?

    @State var showFileImporter = false
    @State var selectedFileURL: URL?
    @State var encryptedExportURL: URL?
    @State var encryptedExportPassword = ""
    @State var isDecryptingEncryptedExport = false
    @State var showingEncryptedExportPasswordSheet = false
    @State var previewRows: [[String]] = []
    @State var headerRowIndex: Int = 0
    @State var columnMapping: [Int: String] = [:]  // Column index -> field name
    @State var currentStep: ImportStep = .selectFile
    @State var errorMessage: String?
    @State var isProcessing = false
    @State var importedCount = 0
    @State var selectedDateFormat: DateFormatOption? = nil
    @State var selectedImportSource: ImportSource = .custom
    @State var hasLoadedPreview = false
    @State var importTask: Task<Void, Never>? = nil
		    @State var stagedTransactions: [ImportedTransaction] = []
		    @State var importProgress: ImportProgressState? = nil

        @State var importProcessingResult: TransactionProcessor.Result? = nil
        @State var showingImportProcessingReview = false
        @State var importedFileName: String? = nil

    @State var showingReview = false
    @State var transferSuggestions: [ImportTransferSuggester.Suggestion] = []
    @State var selectedTransferSuggestionIDs: Set<String> = []
    @State var showingTransferSuggestionSheet = false
    @State var transferSuggestionCount: Int = 0
    @State var editingTransferLink: TransferLinkEditorDestination?

		@State var defaultAccount: Account?
		@State var signConvention: AmountSignConvention?
    @State var showingImportOptionsSheet = false
    @State var hasConfiguredImportOptionsThisRun = false

	    @State var importOptions = ImportProcessingOptions(
	        normalizePayee: true,
	        applyAutoRules: true,
	        detectDuplicates: true,
	        suggestTransfers: true,
	        saveProcessingHistory: false
	    )

	// Account Mapping State
		@State var importedAccounts: [String] = []
		@State var accountMapping: [String: Account] = [:]
			@State var accountCreationTarget: AccountCreationTarget? = nil
			@State var newAccountName: String = ""
			@State var newAccountType: AccountType = .chequing
			@State var newAccountBalanceInput: String = ""
			@State var showingCreateAccountSheet: Bool = false
    
    // Category Mapping State
    @State var importedCategories: [String] = [] 
    @State var categoryMapping: [String: Category] = [:] 
    @State var allCategories: [Category] = []
    @State var allGroups: [CategoryGroup] = []
    @State var categoryCreationTarget: CategoryCreationTarget? = nil 
    @State var newCategoryName: String = ""
    @State var newCategoryGroup: CategoryGroup? = nil

    // Tag Mapping State
    @State var importedTags: [String] = []
    @State var ignoredImportedTags: Set<String> = []
    @State var tagMapping: [String: TransactionTag] = [:]
    @State var allTransactionTags: [TransactionTag] = []
    @State var tagCreationTarget: TagCreationTarget? = nil
    @State var newTagName: String = ""
    @State var newTagColorHex: String = TagColorPalette.defaultHex
    
    // Group Creation State
    @State var isCreatingNewGroup = false
    @State var newGroupNameRaw: String = ""
    @State var newGroupType: CategoryGroupType = .expense

    // Bulk Category Creation State
    @State var showingBulkCategoryCreation = false
    @State var bulkCategoryGroup: CategoryGroup? = nil
    @State var bulkCreateNewGroup = false
    @State var bulkNewGroupName: String = ""
    @State var bulkNewGroupType: CategoryGroupType = .expense
    @State var selectedUnmappedCategories: Set<String> = []
    @State var bulkGroupingMode: BulkGroupingMode = .smart
    @State var bulkCategoryAssignments: [String: CategoryGroup] = [:]
    @State var bulkAssignNewGroupToSelection = true
    @State var bulkCreatedGroups: [CategoryGroup] = []

    enum BulkGroupingMode: String, CaseIterable, Identifiable {
        case smart = "Smart"
        case single = "Single"
        case custom = "Custom"

        var id: String { rawValue }
    }
    

    enum ImportStep {
		case selectFile
		case selectHeader
		case mapColumns
		case preview
		case importing // Parsing phase
		case mapAccounts
		case mapCategories // New step
		case mapTags
		case review    // Duplicate check & Review phase
		case complete
	}

    enum WizardStep: Int, CaseIterable {
        case file = 0
        case map = 1
        case review = 2
        case `import` = 3

        var title: String {
            switch self {
            case .file: return "File"
            case .map: return "Map"
            case .review: return "Review"
            case .import: return "Imported"
            }
        }
    }

    struct TransferLinkEditorDestination: Identifiable, Equatable {
        let id: UUID
    }

    var lastUsedSource: ImportSource? {
        guard let rawValue = settings.lastUsedImportSource else { return nil }
        return ImportSource.allCases.first { $0.rawValue == rawValue }
    }

    var currencyCode: String {
        settings.currencyCode
    }

    var lastUsedSourceRaw: String? {
        get { settings.lastUsedImportSource }
        nonmutating set { settings.lastUsedImportSource = newValue }
    }

    var normalizePayeeOnImport: Bool {
        settings.normalizePayeeOnImport
    }

    var applyAutoRulesOnImport: Bool {
        settings.applyAutoRulesOnImport
    }

    var detectDuplicatesOnImport: Bool {
        settings.detectDuplicatesOnImport
    }

    var suggestTransfersOnImport: Bool {
        settings.suggestTransfersOnImport
    }

    var saveProcessingHistory: Bool {
        settings.saveProcessingHistory
    }

    var sortedImportSources: [ImportSource] {
        ImportSource.sortedSources(currencyCode: settings.currencyCode, lastUsed: lastUsedSource)
    }

	var currentWizardStep: WizardStep {
		switch currentStep {
		case .selectFile:
			return .file
		case .selectHeader, .mapColumns, .mapAccounts, .mapCategories, .mapTags:
			return .map
		case .preview, .review:
			return .review
		case .importing, .complete:
			return .import
		}
	}
    
    var body: some View {
        NavigationStack {
            importContainer
        }
    }

    private var importContainer: some View {
        importBaseView
            .safeAreaInset(edge: .top) {
                wizardChrome
            }
            .navigationTitle(initialAccount == nil ? "Import Data" : "Import")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar { importToolbar }
            .alert("Error", isPresented: isShowingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showFileImporter) {
                CSVDocumentPicker(
                    onPick: { urls in
                        handleFileSelection(.success(urls))
                    },
                    onCancel: {
                        showFileImporter = false
                    },
                    onError: { error in
                        handleFileSelection(.failure(error))
                    }
                )
            }
            .sheet(isPresented: $showingImportOptionsSheet) {
                importOptionsSheet
            }
            .sheet(isPresented: $showingEncryptedExportPasswordSheet) {
                encryptedExportPasswordSheet
            }
            .sheet(isPresented: $showingImportProcessingReview) {
                if let result = importProcessingResult {
                    ImportProcessingReviewView(
                        result: result,
                        fileName: importedFileName,
                        options: importOptions
                    )
                }
            }
            .sheet(isPresented: $showingCreateAccountSheet) {
                createAccountSheet
            }
            .onDisappear {
                importTask?.cancel()
                importTask = nil
                if let url = selectedFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                if let url = encryptedExportURL {
                    try? FileManager.default.removeItem(at: url)
                }
                selectedFileURL = nil
                encryptedExportURL = nil
                encryptedExportPassword = ""
            }
            .overlay {
                if let progress = importProgress {
                    ImportProgressOverlay(
                        progress: progress,
                        onCancel: progress.canCancel ? { cancelBackgroundWork() } : nil
                    )
                    .transition(.opacity)
                }
            }
    }

    private var importBaseView: some View {
        Group {
            switch currentStep {
            case .selectFile:
                fileSelectionView
            case .selectHeader:
                headerSelectionView
            case .mapColumns:
                columnMappingView
            case .preview:
                previewView
            case .importing:
                importingView
            case .mapAccounts:
                accountMappingView
            case .mapCategories:
                categoryMappingView
            case .mapTags:
                tagMappingView
            case .review:
                reviewImportView
            case .complete:
                completeView
            }
        }
    }

    private var wizardChrome: some View {
        VStack(spacing: 0) {
            wizardStepIndicator
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ToolbarContentBuilder
    private var importToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { cancelImport() }
        }
        ToolbarItem(placement: .primaryAction) {
            Group {
                switch currentStep {
                case .selectHeader:
                    Button("Next") {
                        autoMapColumns()
                        currentStep = .mapColumns
                    }
                    .disabled(!canAdvanceFromHeader)
                case .mapColumns:
                    Button("Next") { currentStep = .preview }
                        .disabled(!canAdvanceToPreview)
                case .preview:
                    Button("Import") {
                        // Prompt for processing options here (instead of Settings).
                        if !hasConfiguredImportOptionsThisRun {
                            importOptions = ImportProcessingOptions(
                                normalizePayee: settings.normalizePayeeOnImport,
                                applyAutoRules: settings.applyAutoRulesOnImport,
                                detectDuplicates: settings.detectDuplicatesOnImport,
                                suggestTransfers: settings.suggestTransfersOnImport,
                                saveProcessingHistory: settings.saveProcessingHistory
                            )
                        }
                        showingImportOptionsSheet = true
                    }
                    .disabled(defaultAccount == nil || signConvention == nil)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var importOptionsSheet: some View {
        NavigationStack {
            ImportProcessingOptionsSheet(
                options: $importOptions,
                onUseOnce: {
                    hasConfiguredImportOptionsThisRun = true
                    showingImportOptionsSheet = false
                    requestImportConfirmation()
                },
                onMakeDefault: {
                    settings.normalizePayeeOnImport = importOptions.normalizePayee
                    settings.applyAutoRulesOnImport = importOptions.applyAutoRules
                    settings.detectDuplicatesOnImport = importOptions.detectDuplicates
                    settings.suggestTransfersOnImport = importOptions.suggestTransfers
                    settings.saveProcessingHistory = importOptions.saveProcessingHistory
                    hasConfiguredImportOptionsThisRun = true
                    showingImportOptionsSheet = false
                    requestImportConfirmation()
                },
                onCancel: {
                    showingImportOptionsSheet = false
                }
            )
        }
    }

    private var createAccountSheet: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                        Text("Name")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Enter account name", text: $newAccountName)
                            .textInputAutocapitalization(.words)
                    }

                    Picker("Account Type", selection: $newAccountType) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                        Text("Current Balance")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        HStack(spacing: AppDesign.Theme.Spacing.compact) {
                            Text(currencySymbol(for: settings.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField("0", text: $newAccountBalanceInput)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreateAccountSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { createAccountAndReturnToImport() }
                        .disabled(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    init(initialAccount: Account? = nil) {
        self.initialAccount = initialAccount
    }

}
