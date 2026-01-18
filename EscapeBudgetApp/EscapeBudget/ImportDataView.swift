import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
struct ImportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: AppNavigator
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("hasNotifications") private var hasNotifications = false
    @AppStorage("transactions.normalizePayeeOnImport") private var normalizePayeeOnImport = true
    @AppStorage("transactions.applyAutoRulesOnImport") private var applyAutoRulesOnImport = true
    @AppStorage("transactions.detectDuplicatesOnImport") private var detectDuplicatesOnImport = true
    @AppStorage("transactions.suggestTransfersOnImport") private var suggestTransfersOnImport = true
    @AppStorage("transactions.saveProcessingHistory") private var saveProcessingHistory = false
    @AppStorage("import.lastUsedSource") private var lastUsedSourceRaw: String?
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \Account.name) private var accounts: [Account]

    let initialAccount: Account?

    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var encryptedExportURL: URL?
    @State private var encryptedExportPassword = ""
    @State private var isDecryptingEncryptedExport = false
    @State private var showingEncryptedExportPasswordSheet = false
    @State private var previewRows: [[String]] = []
    @State private var headerRowIndex: Int = 0
    @State private var columnMapping: [Int: String] = [:]  // Column index -> field name
    @State private var currentStep: ImportStep = .selectFile
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var importedCount = 0
    @State private var selectedDateFormat: DateFormatOption? = nil
    @State private var selectedImportSource: ImportSource = .custom
    @State private var hasLoadedPreview = false
    @State private var importTask: Task<Void, Never>? = nil
	    @State private var stagedTransactions: [ImportedTransaction] = []
	    @State private var importProgress: ImportProgressState? = nil

        @State private var importProcessingResult: TransactionProcessor.Result? = nil
        @State private var showingImportProcessingReview = false
        @State private var importedFileName: String? = nil

    @State private var showingReview = false
    @State private var transferSuggestions: [ImportTransferSuggester.Suggestion] = []
    @State private var selectedTransferSuggestionIDs: Set<String> = []
    @State private var showingTransferSuggestionSheet = false
    @State private var transferSuggestionCount: Int = 0
    @State private var editingTransferLink: TransferLinkEditorDestination?

	@State private var defaultAccount: Account?
	@State private var signConvention: AmountSignConvention?
	@State private var showingSignConfirmation = false
    @State private var showingImportOptionsSheet = false
    @State private var hasConfiguredImportOptionsThisRun = false

    @State private var importOptions = ImportProcessingOptions(
        normalizePayee: true,
        applyAutoRules: true,
        detectDuplicates: true,
        suggestTransfers: true,
        saveProcessingHistory: false
    )

	// Account Mapping State
	@State private var importedAccounts: [String] = []
	@State private var accountMapping: [String: Account] = [:]
		@State private var accountCreationTarget: AccountCreationTarget? = nil
		@State private var newAccountName: String = ""
		@State private var newAccountType: AccountType = .chequing
		@State private var newAccountBalanceInput: String = ""
		@State private var showingCreateAccountSheet: Bool = false
    
    // Category Mapping State
    @State private var importedCategories: [String] = [] 
    @State private var categoryMapping: [String: Category] = [:] 
    @State private var allCategories: [Category] = []
    @State private var allGroups: [CategoryGroup] = []
    @State private var categoryCreationTarget: CategoryCreationTarget? = nil 
    @State private var newCategoryName: String = ""
    @State private var newCategoryGroup: CategoryGroup? = nil

    // Tag Mapping State
    @State private var importedTags: [String] = []
    @State private var ignoredImportedTags: Set<String> = []
    @State private var tagMapping: [String: TransactionTag] = [:]
    @State private var allTransactionTags: [TransactionTag] = []
    @State private var tagCreationTarget: TagCreationTarget? = nil
    @State private var newTagName: String = ""
    @State private var newTagColorHex: String = TagColorPalette.defaultHex
    
    // Group Creation State
    @State private var isCreatingNewGroup = false
    @State private var newGroupNameRaw: String = ""
    @State private var newGroupType: CategoryGroupType = .expense

    // Bulk Category Creation State
    @State private var showingBulkCategoryCreation = false
    @State private var bulkCategoryGroup: CategoryGroup? = nil
    @State private var bulkCreateNewGroup = false
    @State private var bulkNewGroupName: String = ""
    @State private var bulkNewGroupType: CategoryGroupType = .expense
    @State private var selectedUnmappedCategories: Set<String> = []
    

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

    private enum WizardStep: Int, CaseIterable {
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

    private struct TransferLinkEditorDestination: Identifiable, Equatable {
        let id: UUID
    }

    private var lastUsedSource: ImportSource? {
        guard let rawValue = lastUsedSourceRaw else { return nil }
        return ImportSource.allCases.first { $0.rawValue == rawValue }
    }

    private var sortedImportSources: [ImportSource] {
        ImportSource.sortedSources(currencyCode: currencyCode, lastUsed: lastUsedSource)
    }

	private var currentWizardStep: WizardStep {
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
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    wizardStepIndicator
                    Divider()
                }
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle(initialAccount == nil ? "Import Data" : "Import")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
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
                                        normalizePayee: normalizePayeeOnImport,
                                        applyAutoRules: applyAutoRulesOnImport,
                                        detectDuplicates: detectDuplicatesOnImport,
                                        suggestTransfers: suggestTransfersOnImport,
                                        saveProcessingHistory: saveProcessingHistory
                                    )
                                }
                                showingImportOptionsSheet = true
                            }
                                .disabled(defaultAccount == nil)
                                .confirmationDialog(
                                    "Confirm Amount Signs",
                                    isPresented: $showingSignConfirmation,
                                    titleVisibility: .visible
                                ) {
                                    Button("Positive = Income") { beginImport(signConvention: .positiveIsIncome) }
                                    Button("Positive = Expense") { beginImport(signConvention: .positiveIsExpense) }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("How should Escape Budget interpret positive/negative numbers in your CSV before importing?")
                                }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
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
                NavigationStack {
                    ImportProcessingOptionsSheet(
                        options: $importOptions,
                        onUseOnce: {
                            hasConfiguredImportOptionsThisRun = true
                            showingImportOptionsSheet = false
                            requestImportConfirmation()
                        },
                        onMakeDefault: {
                            normalizePayeeOnImport = importOptions.normalizePayee
                            applyAutoRulesOnImport = importOptions.applyAutoRules
                            detectDuplicatesOnImport = importOptions.detectDuplicates
                            suggestTransfersOnImport = importOptions.suggestTransfers
                            saveProcessingHistory = importOptions.saveProcessingHistory
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
                NavigationStack {
                    Form {
                        Section("Details") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Enter account name", text: $newAccountName)
                                    .textInputAutocapitalization(.words)
                            }

                            Picker("Account Type", selection: $newAccountType) {
                                ForEach(AccountType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Balance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(currencySymbol(for: currencyCode))
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
                .presentationDetents([.medium])
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
    }

    init(initialAccount: Account? = nil) {
        self.initialAccount = initialAccount
    }

    private var wizardStepIndicator: some View {
        HStack(spacing: 10) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentWizardStep.rawValue ? AppColors.tint(for: appColorMode) : Color.gray.opacity(0.3))
                            .frame(width: 26, height: 26)

                        if step.rawValue < currentWizardStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.caption.bold())
                                .foregroundColor(step.rawValue <= currentWizardStep.rawValue ? .white : .gray)
                        }
                    }

                    if step == currentWizardStep {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: step == currentWizardStep ? .infinity : 34, alignment: .leading)
                .clipped()
                .layoutPriority(step == currentWizardStep ? 1 : 0)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: currentWizardStep)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    private func cancelBackgroundWork() {
        importTask?.cancel()
        importTask = nil
        isProcessing = false
        importProgress = nil
        if currentStep == .importing {
            currentStep = .preview
        }
    }

    private func cancelImport() {
        cancelBackgroundWork()
        hasConfiguredImportOptionsThisRun = false
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
            selectedFileURL = nil
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
            encryptedExportURL = nil
        }
        dismiss()
    }

	    private struct ImportProgressState: Equatable {
	        enum Phase: String {
	            case parsing = "Parsing CSV"
	            case preparing = "Preparing"
	            case saving = "Saving"
                case processing = "Processing"
	        }

        var title: String
        var phase: Phase
        var message: String
        var current: Int
        var total: Int?
        var canCancel: Bool
    }

    private struct ImportProgressOverlay: View {
        let progress: ImportProgressState
        let onCancel: (() -> Void)?

        private var fractionComplete: Double? {
            guard let total = progress.total, total > 0 else { return nil }
            return min(1, Double(progress.current) / Double(total))
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.title)
                            .font(.headline)

                        Text(progress.phase.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        if let fractionComplete {
                            ProgressView(value: fractionComplete)
                        } else {
                            ProgressView()
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(progress.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer()

                            if let total = progress.total {
                                Text("\(min(progress.current, total)) / \(total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else if progress.current > 0 {
                                Text("\(progress.current)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    if let onCancel {
                        Button("Cancel Import", role: .destructive) {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }
    
    private var canAdvanceFromHeader: Bool {
        hasLoadedPreview && !previewRows.isEmpty
    }
    
    private var canAdvanceToPreview: Bool {
        // Ensure at least Date and Amount are mapped, or other logic
        let mapped = columnMapping.values
        return mapped.contains("Date") && (mapped.contains("Amount") || (mapped.contains("Inflow") || mapped.contains("Outflow")))
    }
    
    // MARK: - File Selection View
	    private var fileSelectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(AppColors.tint(for: appColorMode))

            VStack(spacing: 12) {
                Text("Import Data from CSV")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select a CSV file to import transaction data. Supports large files and various bank formats.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Template")
                    .font(.headline)

                Menu {
                    ForEach(sortedImportSources) { source in
                        Button {
                            selectedImportSource = source
                            lastUsedSourceRaw = source.rawValue
                            autoMapColumns()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(source.rawValue)
                                Text(source.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedImportSource.rawValue)
                                .foregroundColor(.primary)
                            Text(selectedImportSource.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
	                Text(initialAccount == nil ? "Default Account" : "Destination Account")
	                    .font(.headline)
	                if accounts.isEmpty {
	                    VStack(alignment: .leading, spacing: 10) {
	                        Text("Create an account to import transactions into.")
	                            .font(.subheadline)
	                            .foregroundColor(.secondary)

	                        Button {
	                            beginCreateAccountFromFileSelection()
	                        } label: {
	                            Label("Create Account", systemImage: "plus.circle")
	                                .frame(maxWidth: .infinity)
	                        }
	                        .buttonStyle(.borderedProminent)
	                    }
	                    .padding(12)
	                    .background(Color(.secondarySystemGroupedBackground))
	                    .cornerRadius(12)
	                } else {
	                    if let initialAccount {
                        let destination = defaultAccount ?? initialAccount
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(destination.name)
                                        .font(.body.weight(.semibold))
                                    Text(destination.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(accounts) { account in
                                        Button {
                                            defaultAccount = account
                                        } label: {
                                            HStack {
                                                Text(account.name)
                                                if account.persistentModelID == destination.persistentModelID {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Change")
                                }
                            }

                            Text("If your CSV includes an Account column and you map it, Escape Budget will import per-row accounts; otherwise it will use this destination account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    } else {
                        Picker("Default Account", selection: $defaultAccount) {
                            Text("Select").tag(Optional<Account>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(.horizontal)

            Button(action: { showFileImporter = true }) {
                Label("Select CSV File", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .controlSize(.large)
            .disabled(accounts.isEmpty)
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
	        .onAppear {
	            if defaultAccount == nil {
	                defaultAccount = initialAccount ?? accounts.first
	            }
	        }
	    }

	    private func beginCreateAccountFromFileSelection() {
	        newAccountName = ""
	        newAccountType = .chequing
	        newAccountBalanceInput = ""
	        showingCreateAccountSheet = true
	    }

	    @MainActor
	    private func createAccountAndReturnToImport() {
	        let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }

	        if let existing = accounts.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	            defaultAccount = existing
	            showingCreateAccountSheet = false
	            return
	        }

	        let balance = ImportParser.parseAmount(newAccountBalanceInput) ?? 0
	        let account = Account(name: trimmed, type: newAccountType, balance: balance)
	        modelContext.insert(account)
	        guard modelContext.safeSave(context: "ImportDataView.createAccountAndReturnToImport", showErrorToUser: false) else {
                modelContext.delete(account)
                errorMessage = "Couldn’t create the account. Please try again."
                return
            }
	        defaultAccount = account
	        showingCreateAccountSheet = false
	    }

    // MARK: - Header Selection View
    private var headerSelectionView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Header Row")
                    .font(.headline)
                Text("Tap the row that contains column names (Date, Amount, etc.)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            headerPreviewTable
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Date Format (Optional)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Picker("Date Format", selection: $selectedDateFormat) {
                        Text("Auto Detect").tag(nil as DateFormatOption?)
                        ForEach(DateFormatOption.allCases) { format in
                            Text(format.rawValue).tag(Optional(format))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Spacer()
                }

                Text("If dates aren't parsing correctly, specify the format used in your file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var headerPreviewTable: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<previewRows.count, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        // Row Number
                        Text("\(rowIndex + 1)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .center)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                        
                        // Columns
                        ForEach(Array(previewRows[rowIndex].enumerated()), id: \.offset) { column in
                            Text(column.element.isEmpty ? " " : column.element)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .background(rowBackground(for: rowIndex))
                                .contentShape(Rectangle())
                        }
                    }
                    .background(rowBackground(for: rowIndex))
                    .border(rowIndex == headerRowIndex ? AppColors.tint(for: appColorMode) : Color.clear, width: 2)
                    .onTapGesture {
                        headerRowIndex = rowIndex
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private func rowBackground(for index: Int) -> Color {
        if index == headerRowIndex {
            return AppColors.tint(for: appColorMode).opacity(0.1)
        }
        return index % 2 == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5)
    }

    // MARK: - Column Mapping View
    private var columnMappingView: some View {
        VStack(spacing: 0) {
            if previewRows.indices.contains(headerRowIndex) {
                 List {
                     Section {
                         ForEach(0..<previewRows[headerRowIndex].count, id: \.self) { colIndex in
                             let header = previewRows[headerRowIndex][colIndex]
                             if !header.isEmpty {
                                 ColumnMappingRowView(
                                     header: header,
                                     colIndex: colIndex,
                                     columnMapping: $columnMapping,
                                     previewValue: getPreviewValue(col: colIndex)
                                 )
                             }
                         }
                     } header: {
                         Text("Map Columns")
                     } footer: {
                         let valid = canAdvanceToPreview
                         if !valid {
                             Text("Please map at least Date and Amount columns.")
                                 .foregroundColor(AppColors.danger(for: appColorMode))
                         }
                     }
                 }
            } else {
                Text("Invalid header row selected")
            }
        }
    }
    
    private func getPreviewValue(col: Int) -> String? {
        // Show value from first data row (header + 1)
        let dataRowIdx = headerRowIndex + 1
        if previewRows.indices.contains(dataRowIdx), previewRows[dataRowIdx].indices.contains(col) {
            return previewRows[dataRowIdx][col]
        }
        return nil
    }

    // MARK: - Preview View
    private var previewView: some View {
        List {
            Section("Summary") {
                LabeledContent("File", value: selectedFileURL?.lastPathComponent ?? "Unknown")
                LabeledContent("Header Row", value: "\(headerRowIndex + 1)")
                LabeledContent("Mapped Columns", value: "\(columnMapping.values.filter { $0 != "skip" }.count)")
            }

            Section("Import Settings") {
                if accounts.isEmpty {
                    Text("Create an account first, then import transactions.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Default Account", selection: $defaultAccount) {
                        Text("Select").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                }

                let hasAccountColumn = columnMapping.values.contains("Account")
                if hasAccountColumn {
                    Text("Account column is mapped; Escape Budget will try to match accounts by name per row and fall back to the default account when missing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                LabeledContent("Amount Signs") {
                    Text(signConvention?.rawValue ?? "Will ask on import")
                        .foregroundColor(.secondary)
                }
            }

	            Section {
	                LabeledContent("This import", value: importOptions.summary)

	                Button {
	                    hasConfiguredImportOptionsThisRun = true
	                    showingImportOptionsSheet = true
	                } label: {
	                    Label("Review processing options", systemImage: "slider.horizontal.3")
	                }
	            } header: {
	                Text("Processing")
	            } footer: {
	                Text("These options control payee cleanup, auto rules, duplicate detection, and transfer suggestions for this import.")
	            }
            
            Section("Data Preview (First 5 Items)") {
                let dataRows = Array(previewRows.dropFirst(headerRowIndex + 1).prefix(5))
                ForEach(0..<dataRows.count, id: \.self) { i in
                    let row = dataRows[i]
                    if let tx = createTransaction(
                        from: row,
                        headers: previewRows[headerRowIndex],
                        columnMapping: columnMapping,
                        dateFormatOption: selectedDateFormat,
                        signConvention: signConvention ?? .positiveIsIncome
                    ) {
                        PreviewTransactionRow(transaction: tx, currencyCode: currencyCode)
                    } else {
                        Text("Row \(i + headerRowIndex + 2): Invalid / Skipped")
                            .font(.caption)
                            .foregroundColor(AppColors.danger(for: appColorMode))
                    }
                }
            }
            
            Section {
                 Text("This will verify your mapping on a few rows. If everything looks good, tap Import.")
                     .font(.caption)
                     .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if !hasConfiguredImportOptionsThisRun {
                importOptions = ImportProcessingOptions(
                    normalizePayee: normalizePayeeOnImport,
                    applyAutoRules: applyAutoRulesOnImport,
                    detectDuplicates: detectDuplicatesOnImport,
                    suggestTransfers: suggestTransfersOnImport,
                    saveProcessingHistory: saveProcessingHistory
                )
            }
        }
    }

    // MARK: - Importing View


    // MARK: - Review Import View
    private var reviewImportView: some View {
        VStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(stagedTransactions.count)")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Duplicates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(stagedTransactions.filter { $0.isDuplicate }.count)")
                                .font(.headline)
                                .foregroundColor(AppColors.warning(for: appColorMode))
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("To Import")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(stagedTransactions.filter { $0.isSelected }.count)")
                                .font(.headline)
                                .foregroundColor(AppColors.success(for: appColorMode))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Summary")
                }
                
                Section {
                    Button(action: toggleExcludeDuplicates) {
                        Label("Exclude All Duplicates", systemImage: "rectangle.badge.xmark")
                    }
                    Button(action: selectAllNonDuplicates) {
                        Label("Select All (Non-Duplicates)", systemImage: "checkmark.circle")
                    }
                    Button(action: toggleSelectAll) {
                        Label("Toggle Select All", systemImage: "circle.dashed")
                    }
                }

                if importOptions.suggestTransfers {
                    Section {
                        Button {
                            showingTransferSuggestionSheet = true
                        } label: {
                            Label("Review Transfer Suggestions", systemImage: "sparkles")
                        }

                        Button {
                            refreshTransferSuggestions()
                        } label: {
                            Label("Refresh Suggestions", systemImage: "arrow.clockwise")
                        }

                        if transferSuggestionCount > 0 {
                            Text("\(transferSuggestionCount) transfer pair\(transferSuggestionCount == 1 ? "" : "s") linked.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Transfer Suggestions")
                    } footer: {
                        Text("Review suggested pairs before linking. Linking clears categories and excludes them from income/expense stats.")
                    }
                }
                
                Section("Transactions") {
                    ForEach($stagedTransactions) { $tx in
                        HStack {
                            Image(systemName: tx.isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(tx.isSelected ? AppColors.tint(for: appColorMode) : .gray)
                                .onTapGesture {
                                    tx.isSelected.toggle()
                                }
                            
                            VStack(alignment: .leading) {
                                Text(tx.payee)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if tx.kind == .transfer, tx.transferID != nil {
                                    Text("Transfer (linked)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.tint(for: appColorMode).opacity(0.12))
                                        .foregroundColor(AppColors.tint(for: appColorMode))
                                        .cornerRadius(4)
                                }
                                
                                if let raw = tx.rawCategory {
                                    if let mapped = categoryMapping[raw] {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                            Text(mapped.name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(AppColors.success(for: appColorMode).opacity(0.15))
                                        .foregroundColor(AppColors.success(for: appColorMode))
                                        .cornerRadius(4)
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                            Text("Unmapped: \(raw)")
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(AppColors.warning(for: appColorMode).opacity(0.15))
                                        .foregroundColor(AppColors.warning(for: appColorMode))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(tx.amount.formatted(.currency(code: currencyCode)))
                                    .font(.body)
                                    .foregroundColor(tx.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)

                                if tx.kind == .transfer, let id = tx.transferID {
                                    Button {
                                        editingTransferLink = TransferLinkEditorDestination(id: id)
                                    } label: {
                                        Label("Linked", systemImage: "link")
                                            .font(.caption2)
                                            .labelStyle(.iconOnly)
                                            .foregroundStyle(AppColors.tint(for: appColorMode))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Edit linked transfer")
                                }
                                
                                if tx.isDuplicate {
                                    Text("Duplicate")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.warning(for: appColorMode).opacity(0.2))
                                        .foregroundColor(AppColors.warning(for: appColorMode))
                                        .cornerRadius(4)

                                    if let reason = tx.duplicateReason, !reason.isEmpty {
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tx.isSelected.toggle()
                        }
                    }
                }
            }
            
            Button(action: { performFinalImport() }) {
                Text("Finish Import (\(stagedTransactions.filter { $0.isSelected }.count))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .disabled(stagedTransactions.filter { $0.isSelected }.isEmpty)
        }
        .sheet(isPresented: $showingTransferSuggestionSheet) {
            NavigationStack {
                ImportTransferSuggestionsView(
                    currencyCode: currencyCode,
                    suggestions: transferSuggestions,
                    selectedIDs: $selectedTransferSuggestionIDs,
                    transactionLookup: { id in stagedTransactions.first(where: { $0.id == id }) },
                    accountNameFor: accountNameForImported(_:),
                    onRefresh: { refreshTransferSuggestions() },
                    onLinkSelected: { linkSelectedTransferSuggestions() }
                )
            }
        }
        .sheet(item: $editingTransferLink) { destination in
            NavigationStack {
                ImportTransferLinkEditor(
                    transferID: destination.id,
                    currencyCode: currencyCode,
                    onUnlink: { unlinkTransfer(id: destination.id) },
                    legsLookup: { id in stagedTransactions.filter { $0.transferID == id } },
                    accountNameFor: accountNameForImported(_:)
                )
            }
        }
    }
    
    private func toggleExcludeDuplicates() {
        for index in stagedTransactions.indices {
            if stagedTransactions[index].isDuplicate {
                stagedTransactions[index].isSelected = false
            }
        }
    }

    private func selectAllNonDuplicates() {
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !stagedTransactions[index].isDuplicate
        }
    }
    
    // MARK: - Category Mapping View
	    /// Categories from the import that haven't been mapped yet
	    private var unmappedCategories: [String] {
	        importedCategories.filter { categoryMapping[$0] == nil }
	    }

	    // MARK: - Account Mapping View
	    private var unmappedAccounts: [String] {
	        importedAccounts.filter { accountMapping[$0] == nil }
	    }

	    private var accountMappingView: some View {
	        VStack {
	            Text("Map Accounts")
	                .font(.headline)
	                .padding()

	            Text("Match account names from your file to accounts in Escape Budget.")
	                .font(.caption)
	                .foregroundColor(.secondary)

	            List {
	                Section {
	                    HStack {
	                        Label("\(importedAccounts.count - unmappedAccounts.count) mapped", systemImage: "checkmark.circle.fill")
	                            .foregroundColor(AppColors.success(for: appColorMode))
	                        Spacer()
	                        Label("\(unmappedAccounts.count) unmapped", systemImage: "circle.dashed")
	                            .foregroundColor(.secondary)
	                    }
	                    .font(.caption)
	                } header: {
	                    Text("Status")
	                }

	                Section {
	                    ForEach(importedAccounts, id: \.self) { raw in
	                        HStack {
	                            Text(raw)
	                                .font(.body)
	                            Spacer()

	                            Menu {
	                                Button("Create '\(raw)'...") {
	                                    startCreatingAccount(for: raw, prefill: true)
	                                }

	                                Button("Create New...") {
	                                    startCreatingAccount(for: raw, prefill: false)
	                                }

	                                Divider()

	                                ForEach(accounts) { account in
	                                    Button(account.name) {
	                                        accountMapping[raw] = account
	                                    }
	                                }

	                                Divider()

	                                Button("Use Default Account") {
	                                    accountMapping.removeValue(forKey: raw)
	                                }
	                            } label: {
	                                HStack {
	                                    if let mapped = accountMapping[raw] {
	                                        Text(mapped.name)
	                                            .foregroundColor(.primary)
	                                        Image(systemName: "checkmark.circle.fill")
	                                            .foregroundColor(AppColors.success(for: appColorMode))
	                                    } else {
	                                        Text("Use Default")
	                                            .foregroundColor(.secondary)
	                                        Image(systemName: "chevron.up.chevron.down")
	                                            .font(.caption)
	                                    }
	                                }
	                                .padding(.horizontal, 8)
	                                .padding(.vertical, 4)
	                                .background(Color(.secondarySystemBackground))
	                                .cornerRadius(8)
	                            }
	                        }
	                    }
	                } header: {
	                    Text("Accounts")
	                } footer: {
	                    Text("Unmapped values will be assigned to your selected default account.")
	                }
	            }

	            Button("Next") {
	                prepareCategoryMapping()
	            }
	            .buttonStyle(.borderedProminent)
	            .controlSize(.large)
	            .padding()
	        }
	        .sheet(item: $accountCreationTarget) { target in
	            NavigationStack {
	                Form {
	                    Section {
	                        VStack(alignment: .leading, spacing: 8) {
	                            Text("Imported Value")
	                                .font(.caption)
	                                .foregroundStyle(.secondary)
	                            Text(target.rawAccount)
	                                .font(.headline)
	                        }
	                    }

	                    Section("Details") {
	                        VStack(alignment: .leading, spacing: 4) {
	                            Text("Name")
	                                .font(.caption)
	                                .foregroundStyle(.secondary)
	                            TextField("Enter account name", text: $newAccountName)
	                                .textInputAutocapitalization(.words)
	                        }

	                        Picker("Account Type", selection: $newAccountType) {
	                            ForEach(AccountType.allCases) { type in
	                                Text(type.rawValue).tag(type)
	                            }
	                        }

	                        VStack(alignment: .leading, spacing: 4) {
	                            Text("Starting Balance")
	                                .font(.caption)
	                                .foregroundStyle(.secondary)
	                            HStack(spacing: 8) {
	                                Text(currencySymbol(for: currencyCode))
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
		                    Button("Cancel") { accountCreationTarget = nil }
		                }
	                    ToolbarItem(placement: .confirmationAction) {
	                        Button("Add") {
	                            createAccountFromImportMapping(rawAccount: target.rawAccount)
	                        }
	                        .disabled(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	                    }
	                }
	            }
	            .presentationDetents([.medium])
	        }
	    }

	    private var categoryMappingView: some View {
	        VStack {
	            Text("Map Categories")
	                .font(.headline)
                .padding()

            Text("Match categories from your file to your Escape Budget categories.")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                // Bulk Actions Section
                if !unmappedCategories.isEmpty {
                    Section {
                        Button {
                            prepareBulkCategoryCreation()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppColors.tint(for: appColorMode))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create All Unmapped Categories")
                                        .font(.body)
                                    Text("\(unmappedCategories.count) categories will be created")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    } header: {
                        Text("Quick Actions")
                    }
                }

                // Mapping Status Section
                Section {
                    HStack {
                        Label("\(importedCategories.count - unmappedCategories.count) mapped", systemImage: "checkmark.circle.fill")
                            .foregroundColor(AppColors.success(for: appColorMode))
                        Spacer()
                        Label("\(unmappedCategories.count) unmapped", systemImage: "circle.dashed")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                } header: {
                    Text("Status")
                }

                // Category List Section
                Section {
                    ForEach(importedCategories, id: \.self) { raw in
                        HStack {
                            Text(raw)
                                .font(.body)
                            Spacer()

                            Menu {
                                Button("Create '\(raw)'...") {
                                    startCreatingCategory(for: raw, prefill: true)
                                }

                                Button("Create New...") {
                                    startCreatingCategory(for: raw, prefill: false)
                                }

                                Divider()

                                ForEach(allCategories) { cat in
                                    Button(cat.name) {
                                        categoryMapping[raw] = cat
                                    }
                                }

                                Button("None (Uncategorized)", role: .destructive) {
                                    categoryMapping[raw] = nil
                                }
                            } label: {
                                HStack {
                                    if let mapped = categoryMapping[raw] {
                                        Text(mapped.name)
                                            .foregroundColor(.primary)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.success(for: appColorMode))
                                    } else {
                                        Text("Select Category")
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                    }
                } header: {
                    Text("Categories")
                }
            }

            Button("Next") {
                prepareTagMappingOrReview()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .sheet(item: $categoryCreationTarget) { target in
            NavigationStack {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Imported Value:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .font(.headline)
                        }
                    }
                    
                    Section("New Category Details") {
                        VStack(alignment: .leading) {
                            TextField("Category Name", text: $newCategoryName)
                            if newCategoryName != target.rawCategory {
                                Button("Use Imported Name") {
                                    newCategoryName = target.rawCategory
                                }
                                .font(.caption)
                                .foregroundStyle(AppColors.tint(for: appColorMode))
                            }
                        }
                        
                        Toggle("Create New Group", isOn: $isCreatingNewGroup)
                        
                        if isCreatingNewGroup {
                            VStack(alignment: .leading) {
                                TextField("New Group Name", text: $newGroupNameRaw)
                                if newGroupNameRaw != target.rawCategory {
                                    Button("Use Imported Name") {
                                        newGroupNameRaw = target.rawCategory
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AppColors.tint(for: appColorMode))
                                }
                            }
                            Picker("Type", selection: $newGroupType) {
                                ForEach(CategoryGroupType.allCases.filter { $0 != .transfer }, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                        } else {
                            Picker("Group", selection: $newCategoryGroup) {
                                Text("Select Group").tag(Optional<CategoryGroup>.none)
                                ForEach(allGroups.filter { $0.type != .transfer }) { group in
                                    Text(group.name).tag(Optional(group))
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Create Category")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { categoryCreationTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createCategory(for: target.rawCategory)
                        }
                        .disabled(newCategoryName.isEmpty || (isCreatingNewGroup ? newGroupNameRaw.isEmpty : newCategoryGroup == nil))
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
        .sheet(isPresented: $showingBulkCategoryCreation) {
            NavigationStack {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create \(selectedUnmappedCategories.count) Categories")
                                .font(.headline)
                            Text("These categories will be created and automatically mapped to your import data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        ForEach(unmappedCategories, id: \.self) { raw in
                            HStack {
                                Image(systemName: selectedUnmappedCategories.contains(raw) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUnmappedCategories.contains(raw) ? AppColors.tint(for: appColorMode) : .gray)
                                Text(raw)
                                    .font(.body)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedUnmappedCategories.contains(raw) {
                                    selectedUnmappedCategories.remove(raw)
                                } else {
                                    selectedUnmappedCategories.insert(raw)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Categories to Create")
                            Spacer()
                            if unmappedCategories.count > 1 {
                                Button {
                                    if selectedUnmappedCategories.count == unmappedCategories.count {
                                        selectedUnmappedCategories.removeAll()
                                    } else {
                                        selectedUnmappedCategories = Set(unmappedCategories)
                                    }
                                } label: {
                                    Text(selectedUnmappedCategories.count == unmappedCategories.count ? "Deselect All" : "Select All")
                                        .font(.subheadline)
                                        .foregroundColor(AppColors.tint(for: appColorMode))
                                }
                            }
                        }
                        .textCase(nil)
                    }

                    Section("Destination Group") {
                        Toggle("Create New Group", isOn: $bulkCreateNewGroup)

                        if bulkCreateNewGroup {
                            TextField("Group Name", text: $bulkNewGroupName)
                            Picker("Type", selection: $bulkNewGroupType) {
                                ForEach(CategoryGroupType.allCases.filter { $0 != .transfer }, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                        } else {
                            Picker("Group", selection: $bulkCategoryGroup) {
                                Text("Select Group").tag(Optional<CategoryGroup>.none)
                                ForEach(allGroups.filter { $0.type != .transfer }) { group in
                                    Text(group.name).tag(Optional(group))
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Bulk Create")
                .navigationBarTitleDisplayMode(.inline)
                .globalKeyboardDoneToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingBulkCategoryCreation = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create \(selectedUnmappedCategories.count)") {
                            performBulkCategoryCreation()
                        }
                        .disabled(selectedUnmappedCategories.isEmpty || (bulkCreateNewGroup ? bulkNewGroupName.isEmpty : bulkCategoryGroup == nil))
                    }
                }
            }
            .presentationDetents([.large])
            .solidPresentationBackground()
        }
    }

    private func prepareBulkCategoryCreation() {
        // Pre-select all unmapped categories
        selectedUnmappedCategories = Set(unmappedCategories)
        // Reset group selection - exclude transfer groups
        bulkCategoryGroup = allGroups.filter { $0.type != .transfer }.first
        bulkCreateNewGroup = false
        bulkNewGroupName = ""
        bulkNewGroupType = .expense
        showingBulkCategoryCreation = true
    }

	    private func performBulkCategoryCreation() {
        var targetGroup: CategoryGroup

        var createdGroup: CategoryGroup? = nil
        var createdCategories: [Category] = []

        if bulkCreateNewGroup {
            let newGroup = CategoryGroup(name: bulkNewGroupName, type: bulkNewGroupType)
            modelContext.insert(newGroup)
            allGroups.append(newGroup)
            targetGroup = newGroup
            createdGroup = newGroup
        } else {
            guard let group = bulkCategoryGroup else { return }
            targetGroup = group
        }

        // Create all selected categories
        for rawCategory in selectedUnmappedCategories {
            let newCat = Category(name: rawCategory)
            newCat.group = targetGroup
            modelContext.insert(newCat)
            createdCategories.append(newCat)
            allCategories.append(newCat)
            categoryMapping[rawCategory] = newCat
        }

        // Save context
        guard modelContext.safeSave(context: "ImportDataView.performBulkCategoryCreation", showErrorToUser: false) else {
            if let createdGroup {
                allGroups.removeAll { $0.persistentModelID == createdGroup.persistentModelID }
                modelContext.delete(createdGroup)
            }
            for category in createdCategories {
                allCategories.removeAll { $0.persistentModelID == category.persistentModelID }
                modelContext.delete(category)
            }
            for rawCategory in selectedUnmappedCategories {
                categoryMapping[rawCategory] = nil
            }
            errorMessage = "Couldn’t create categories. Please try again."
            return
        }

        // Close sheet
        showingBulkCategoryCreation = false
    }

	    private func startCreatingCategory(for raw: String, prefill: Bool) {
        newCategoryName = prefill ? raw : ""
        newCategoryGroup = allGroups.first
        
        // Reset/Default group creation state
        isCreatingNewGroup = false
        newGroupNameRaw = ""
        newGroupType = .expense
        
        categoryCreationTarget = CategoryCreationTarget(rawCategory: raw)
    }
    
	    private func createCategory(for raw: String) {
        var targetGroup: CategoryGroup?
        var createdGroup: CategoryGroup? = nil

        if isCreatingNewGroup {
            let newGroup = CategoryGroup(name: newGroupNameRaw, type: newGroupType)
            modelContext.insert(newGroup)
            // Add to local list to keep UI in sync
            allGroups.append(newGroup)
            // Re-sort roughly? Or just append.
            targetGroup = newGroup
            createdGroup = newGroup
        } else {
            targetGroup = newCategoryGroup
        }

        guard let group = targetGroup else { return }
        
        // Create new category
        let newCat = Category(name: newCategoryName)
        newCat.group = group
        modelContext.insert(newCat)
        
        allCategories.append(newCat)
        categoryMapping[raw] = newCat

        // Save context
        guard modelContext.safeSave(context: "ImportDataView.createCategory", showErrorToUser: false) else {
            // Rollback on failure
            if let createdGroup {
                allGroups.removeAll { $0.persistentModelID == createdGroup.persistentModelID }
                modelContext.delete(createdGroup)
            }
            allCategories.removeAll { $0.persistentModelID == newCat.persistentModelID }
            categoryMapping[raw] = nil
            modelContext.delete(newCat)
            errorMessage = "Couldn't create category. Please try again."
            return
        }

        categoryCreationTarget = nil
	    }

		    // MARK: - Account Mapping Helpers

            private func suggestedAccountType(for rawAccountName: String) -> AccountType {
                let lower = rawAccountName.lowercased()
                let tokens = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                let collapsed = lower
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")

                if tokens.contains("mortgage") { return .mortgage }
                if tokens.contains("loan") || tokens.contains("loans") { return .loans }

                if collapsed.contains("lineofcredit") || tokens.contains("loc") {
                    return .lineOfCredit
                }

	                if tokens.contains("credit") ||
	                    collapsed.contains("creditcard") ||
	                    tokens.contains("visa") ||
	                    collapsed.contains("mastercard") ||
	                    tokens.contains("amex") ||
	                    collapsed.contains("americanexpress") ||
	                    tokens.contains("discover") {
	                    return .creditCard
	                }

                if tokens.contains("savings") || tokens.contains("saving") { return .savings }
                if tokens.contains("chequing") || tokens.contains("checking") { return .chequing }

                if tokens.contains("investment") ||
                    tokens.contains("invest") ||
                    tokens.contains("brokerage") ||
                    tokens.contains("rrsp") ||
                    tokens.contains("tfsa") ||
                    tokens.contains("ira") ||
                    tokens.contains("401k") {
                    return .investment
                }

                return .chequing
            }

		    private func startCreatingAccount(for raw: String, prefill: Bool) {
		        newAccountName = prefill ? raw : ""
		        newAccountType = suggestedAccountType(for: raw)
		        newAccountBalanceInput = ""
		        accountCreationTarget = AccountCreationTarget(rawAccount: raw)
		    }

	    private func createAccountFromImportMapping(rawAccount: String) {
	        let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }

	        if let existing = accounts.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	            accountMapping[rawAccount] = existing
	            accountCreationTarget = nil
	            return
	        }

	        let balance = ImportParser.parseAmount(newAccountBalanceInput) ?? 0
	        let account = Account(name: trimmed, type: newAccountType, balance: balance)
	        modelContext.insert(account)
	        accountMapping[rawAccount] = account
	        guard modelContext.safeSave(context: "ImportDataView.createAccountFromImportMapping", showErrorToUser: false) else {
                modelContext.delete(account)
                accountMapping[rawAccount] = nil
                errorMessage = "Couldn’t create the account. Please try again."
                return
            }
	        accountCreationTarget = nil
	    }

	    private func currencySymbol(for code: String) -> String {
	        let formatter = NumberFormatter()
	        formatter.numberStyle = .currency
	        formatter.currencyCode = code
	        formatter.maximumFractionDigits = 0
	        return formatter.currencySymbol ?? "$"
	    }

	    // MARK: - Tag Mapping View
	    private var tagMappingView: some View {
        VStack {
            Text("Map Tags")
                .font(.headline)
                .padding()

            Text("Match tags from your file to your Escape Budget tags.")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(importedTags, id: \.self) { raw in
                    HStack {
                        Text(raw)
                            .font(.body)
                        Spacer()

                        Menu {
                            Button("Create '\(raw)'...") {
                                startCreatingTag(for: raw, prefill: true)
                            }

                            Button("Create New...") {
                                startCreatingTag(for: raw, prefill: false)
                            }

                            Divider()

                            ForEach(allTransactionTags) { tag in
                                Button(tag.name) {
                                    ignoredImportedTags.remove(raw)
                                    tagMapping[raw] = tag
                                }
                            }

                            Divider()

                            Button("Ignore", role: .destructive) {
                                ignoredImportedTags.insert(raw)
                                tagMapping.removeValue(forKey: raw)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if ignoredImportedTags.contains(raw) {
                                    Text("Ignored")
                                        .foregroundColor(AppColors.danger(for: appColorMode))
                                } else if let mapped = tagMapping[raw] {
                                    TransactionTagChip(tag: mapped)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppColors.success(for: appColorMode))
                                } else {
                                    Text("Will Create")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            Button("Next") {
                checkForDuplicates()
                currentStep = .review
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .sheet(item: $tagCreationTarget) { target in
            NavigationStack {
                Form {
                    Section("Imported Value") {
                        Text(target.rawTag)
                            .foregroundStyle(.secondary)
                    }

                    Section("Tag Details") {
                        VStack(alignment: .leading) {
                            TextField("Tag Name", text: $newTagName)
                            if newTagName != target.rawTag {
                                Button("Use Imported Name") {
                                    newTagName = target.rawTag
                                }
                                .font(.caption)
                                .foregroundStyle(AppColors.tint(for: appColorMode))
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                            ForEach(TagColorPalette.options(for: appColorMode), id: \.hex) { option in
                                Circle()
                                    .fill(Color(hex: option.hex) ?? AppColors.tint(for: appColorMode))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(newTagColorHex == option.hex ? Color.primary : Color.clear, lineWidth: 3)
                                    )
                                    .onTapGesture { newTagColorHex = option.hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Create Tag")
                .navigationBarTitleDisplayMode(.inline)
                .globalKeyboardDoneToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { tagCreationTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createTag(for: target.rawTag)
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
    }

    private func startCreatingTag(for raw: String, prefill: Bool) {
        newTagName = prefill ? raw : ""
        newTagColorHex = TagColorPalette.defaultHex(for: appColorMode)
        tagCreationTarget = TagCreationTarget(rawTag: raw)
    }

	    private func createTag(for raw: String) {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = allTransactionTags.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            ignoredImportedTags.remove(raw)
            tagMapping[raw] = existing
            tagCreationTarget = nil
            return
        }

        let nextOrder = (allTransactionTags.map(\.order).max() ?? -1) + 1
        let tag = TransactionTag(name: trimmed, colorHex: newTagColorHex, order: nextOrder)
        modelContext.insert(tag)
        allTransactionTags.append(tag)
        ignoredImportedTags.remove(raw)
        tagMapping[raw] = tag
        tagCreationTarget = nil
    }
    
	    private func toggleSelectAll() {
        let allSelected = stagedTransactions.allSatisfy { $0.isSelected }
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !allSelected
        }
    }

	    private var importingView: some View {
	        VStack(spacing: 24) {
	            if let progress = importProgress {
	                if let totalRaw = progress.total {
	                    let total = max(totalRaw, 1)
	                    let current = min(max(progress.current, 0), total)
	                    ProgressView("Importing…", value: Double(current), total: Double(total))
	                        .progressViewStyle(.circular)

	                    Text("\(current) of \(total)")
	                        .font(.headline)
	                        .foregroundColor(.secondary)
	                } else {
	                    ProgressView("Importing…")
	                        .progressViewStyle(.circular)
	                }
	            } else {
	                ProgressView("Importing…")
	                    .progressViewStyle(.circular)
	            }
            
            Text("Processed: \(importProgress?.current ?? importedCount)")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
		    private var completeView: some View {
            ScrollView {
	            VStack(spacing: 24) {
	                Image(systemName: "checkmark.circle.fill")
	                    .font(.system(size: 80))
	                    .foregroundColor(AppColors.success(for: appColorMode))
                
                Text("Import Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Successfully imported \(importedCount) transactions.")
                    .font(.body)
                    .foregroundColor(.secondary)

                    if let result = importProcessingResult {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("What happened")
                                    .font(.headline)
                                Spacer()
                                if result.summary.changedCount > 0 {
                                    Text("\(result.summary.changedCount) changed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                if result.summary.payeesNormalizedCount > 0 {
                                    summaryLine("Payees cleaned", value: "\(result.summary.payeesNormalizedCount)")
                                }
                                if result.summary.transactionsWithRulesApplied > 0 {
                                    summaryLine("Auto rules applied", value: "\(result.summary.transactionsWithRulesApplied)")
                                }
                                if result.summary.transferSuggestionsInvolvingProcessed > 0 {
                                    summaryLine("Transfer suggestions", value: "\(result.summary.transferSuggestionsInvolvingProcessed)")
                                }
                                if result.summary.changedCount == 0 && result.summary.transferSuggestionsInvolvingProcessed == 0 {
                                    Text("No automated changes were made.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Button {
                                showingImportProcessingReview = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text(result.summary.changedCount > 0 ? "Review Changes" : "Review")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(result.summary.changedCount == 0 && result.summary.transferSuggestionsInvolvingProcessed == 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .padding(.horizontal, 18)
                    }
	                
	                Button("Done") {
                        navigator.selectedTab = .manage
                        navigator.manageNavigator.selectedSection = .transactions
	                    dismiss()
	                }
	                .buttonStyle(.borderedProminent)
	                .controlSize(.large)
	            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func summaryLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Complete View


    // MARK: - Logic

    private var encryptedExportPasswordSheet: some View {
        NavigationStack {
            Form {
                Section("Password") {
                    SecureField("Password", text: $encryptedExportPassword)
                        .textContentType(.password)
                }

                if isDecryptingEncryptedExport {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Decrypting…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Encrypted Export")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let url = encryptedExportURL {
                            try? FileManager.default.removeItem(at: url)
                        }
                        encryptedExportURL = nil
                        encryptedExportPassword = ""
                        showingEncryptedExportPasswordSheet = false
                    }
                    .disabled(isDecryptingEncryptedExport)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") {
                        decryptEncryptedExportAndLoadPreview()
                    }
                    .disabled(isDecryptingEncryptedExport || encryptedExportPassword.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isDecryptingEncryptedExport)
    }

    private func decryptEncryptedExportAndLoadPreview() {
        guard let sourceURL = encryptedExportURL else { return }
        let password = encryptedExportPassword
        guard !password.isEmpty else { return }

        isDecryptingEncryptedExport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ciphertext = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                let plaintext = try EncryptedExportService.decrypt(ciphertext: ciphertext, password: password)

                let tempDir = FileManager.default.temporaryDirectory
                let csvURL = tempDir.appendingPathComponent(UUID().uuidString + ".csv")
                try plaintext.write(to: csvURL, options: [.atomic])
                SensitiveFileProtection.apply(to: csvURL, protection: .completeUnlessOpen)

                try? FileManager.default.removeItem(at: sourceURL)

                DispatchQueue.main.async {
                    self.isDecryptingEncryptedExport = false
                    self.showingEncryptedExportPasswordSheet = false
                    self.encryptedExportPassword = ""
                    self.encryptedExportURL = nil
                    self.selectedFileURL = csvURL
                    self.loadPreview(from: csvURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDecryptingEncryptedExport = false
                    SecurityLogger.shared.logSecurityError(error, context: "ebexport_decrypt")
                    self.errorMessage = "Unable to decrypt that export. Please check your password."
                }
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        showFileImporter = false
        // Reset state
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        encryptedExportURL = nil
        encryptedExportPassword = ""
        showingEncryptedExportPasswordSheet = false

        previewRows = []
        headerRowIndex = 0
        columnMapping = [:]
        importedCount = 0
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Security Scoped Access
            
            // Security Scoped Access
            // Note: If using asCopy: true, the URL might be in our sandbox and startAccessing... returns false.
            // We should attempt to access, but not fail if startAccessing returns false.
            let gotAccess = url.startAccessingSecurityScopedResource()
            // We must keep accessing it while reading. 
            // For the preview reading, we'll stop accessing after reading.
            // For the long import, we'll need to coordinate.
            // PROPER WAY: Copy to temp dir to avoid security scope timeout/issues during long operations.
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileExtension = url.pathExtension.isEmpty ? "csv" : url.pathExtension.lowercased()
            let dstURL = tempDir.appendingPathComponent(UUID().uuidString + "." + fileExtension)
            do {
                // Validate before copying (size, type).
                try SensitiveFileProtection.validateImportableFile(
                    at: url,
                    maxBytes: 50 * 1024 * 1024,
                    allowedExtensions: ["csv", "txt", "tsv", "ebexport", "mmexport"]
                )

                try FileManager.default.copyItem(at: url, to: dstURL)
                if gotAccess { url.stopAccessingSecurityScopedResource() }

                // Ensure sensitive temp files are protected and excluded from backups.
                SensitiveFileProtection.apply(to: dstURL, protection: .completeUnlessOpen)

                if fileExtension == "ebexport" || fileExtension == "mmexport" {
                    self.encryptedExportURL = dstURL
                    self.showingEncryptedExportPasswordSheet = true
                } else {
                    self.selectedFileURL = dstURL
                    loadPreview(from: dstURL)
                }
            } catch {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
                // Clean up temp file on failure
                try? FileManager.default.removeItem(at: dstURL)
                if (error as? SensitiveFileProtection.ValidationError) != nil {
                    errorMessage = error.localizedDescription
                } else {
                    SecurityLogger.shared.logFileOperationError(operation: "copy", path: dstURL.path)
                    errorMessage = "Unable to access the selected file. Please try again."
                }
            }

        case .failure:
            errorMessage = "Unable to select file. Please try again."
        }
    }

    private func loadPreview(from url: URL) {
        isProcessing = true
        Task {
            do {
                // Use RobustCSVParser to read first N rows
                var rows: [[String]] = []
                var count = 0
                for try await row in RobustCSVParser.parse(url: url) {
                    rows.append(row)
                    count += 1
                    if count >= ImportConstants.previewRowLimit { break }
                }
                
                await MainActor.run {
                    self.previewRows = rows
                    self.hasLoadedPreview = true
                    self.currentStep = .selectHeader
                    self.detectHeaderRow()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    SecurityLogger.shared.logSecurityError(error, context: "csv_preview")
                    self.errorMessage = (error as NSError).localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func detectHeaderRow() {
        // Look for keywords in first 10 rows
        let keywords = ["date", "amount", "payee", "description", "memo", "category"]

        for (index, row) in previewRows.prefix(10).enumerated() {
            let hitCount = row.filter { cell in
                let lower = cell.lowercased()
                return keywords.contains { lower.contains($0) }
            }.count

            // If we found at least 2 keywords, assume this is header
            if hitCount >= 2 {
                headerRowIndex = index
                detectImportSource()
                return
            }
        }
    }

    private func detectImportSource() {
        guard !previewRows.isEmpty && previewRows.indices.contains(headerRowIndex) else { return }
        let headers = previewRows[headerRowIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // YNAB - has specific headers
        if headers.contains("outflow") && headers.contains("inflow") && headers.contains("cleared") {
            selectedImportSource = .ynab
            return
        }

        // Mint - has "original description" and "transaction type"
        if headers.contains("original description") || (headers.contains("transaction type") && headers.contains("labels")) {
            selectedImportSource = .mint
            return
        }

        // Monarch - has "merchant" column
        if headers.contains("merchant") && headers.contains("original statement") {
            selectedImportSource = .monarch
            return
        }

        // Chase - has "posting date" or "transaction date"
        if (headers.contains("posting date") || headers.contains("transaction date")) && headers.contains("type") {
            selectedImportSource = .chase
            return
        }

        // Bank of America - has "posted date" and "reference number"
        if headers.contains("posted date") && headers.contains("reference number") {
            selectedImportSource = .bankOfAmerica
            return
        }

        // Citibank - has "debit" and "credit" and "status"
        if headers.contains("debit") && headers.contains("credit") && headers.contains("status") {
            selectedImportSource = .citi
            return
        }

        // Capital One - has "card no." or specific debit/credit format
        if headers.contains("card no.") || (headers.contains("debit") && headers.contains("credit") && headers.contains("category")) {
            selectedImportSource = .capitalOne
            return
        }

        // Discover - has "trans. date" and "post date"
        if headers.contains("trans. date") && headers.contains("post date") {
            selectedImportSource = .discover
            return
        }

        // American Express - has "extended details" or "appears on your statement as"
        if headers.contains("extended details") || headers.contains("appears on your statement as") {
            selectedImportSource = .amex
            return
        }

        // PayPal - has very specific headers
        if headers.contains("from email address") || headers.contains("to email address") || headers.contains("transaction id") {
            selectedImportSource = .paypal
            return
        }

        // Venmo - has "funding source" and "destination"
        if headers.contains("funding source") && headers.contains("destination") {
            selectedImportSource = .venmo
            return
        }

        // Cash App - has "asset type" or "asset price"
        if headers.contains("asset type") || headers.contains("asset price") {
            selectedImportSource = .cashApp
            return
        }

        // RBC - has "cad$" or "usd$" columns
        if headers.contains("cad$") || headers.contains("usd$") || (headers.contains("account type") && headers.contains("cheque number")) {
            selectedImportSource = .rbc
            return
        }

        // TD - has specific "debit", "credit" and "balance" combination
        if headers.contains("debit") && headers.contains("credit") && headers.contains("balance") && !headers.contains("status") {
            selectedImportSource = .td
            return
        }

        // Scotiabank - has "transaction code" or "institution"
        if headers.contains("transaction code") || (headers.contains("institution") && headers.contains("account number")) {
            selectedImportSource = .scotiabank
            return
        }

        // BMO - has "first bank card" or "date posted"
        if headers.contains("first bank card") || (headers.contains("date posted") && headers.contains("transaction type")) {
            selectedImportSource = .bmo
            return
        }

        // CIBC - has "withdrawals" and "deposits"
        if headers.contains("withdrawals") && headers.contains("deposits") {
            selectedImportSource = .cibc
            return
        }

        // National Bank - similar to TD but may have different patterns
        // Will rely on manual selection for now

        // Tangerine - has "transaction" and "name" columns
        if headers.contains("transaction") && headers.contains("name") && headers.contains("memo") {
            selectedImportSource = .tangerine
            return
        }

        // Simplii - has "funds out" and "funds in"
        if headers.contains("funds out") && headers.contains("funds in") {
            selectedImportSource = .simplii
            return
        }

        // Wealthsimple - has "amount (cad)" or "amount (usd)" or "reference #"
        if headers.contains("amount (cad)") || headers.contains("amount (usd)") || headers.contains("reference #") {
            selectedImportSource = .wealthsimple
            return
        }

        // Wells Fargo - harder to detect, leave as custom
        // Default to custom if no match
        selectedImportSource = .custom
    }

    private func autoMapColumns() {
        guard !previewRows.isEmpty && previewRows.indices.contains(headerRowIndex) else { return }
        
        // Reset
        columnMapping = [:]
        
        let headers = previewRows[headerRowIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Helper to find index (only on currently-unmapped columns)
        func findIndex(containing key: String) -> Int? {
            headers.enumerated().first { columnMapping[$0.offset] == nil && $0.element.contains(key) }?.offset
        }
        
        // Helper to find exact match (only on currently-unmapped columns)
        func findExact(_ key: String) -> Int? {
            headers.enumerated().first { columnMapping[$0.offset] == nil && $0.element == key }?.offset
        }
        
        switch selectedImportSource {
        case .ynab:
            // YNAB Headers: Account, Flag, Date, Payee, Category Group/Category, Category Group, Category, Memo, Outflow, Inflow, Cleared
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("payee") { columnMapping[idx] = "Payee" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }
            if let idx = findExact("inflow") { columnMapping[idx] = ColumnType.inflow.rawValue }
            if let idx = findExact("outflow") { columnMapping[idx] = ColumnType.outflow.rawValue }
            
            // YNAB often uses MM/dd/yyyy. Let's try to set hint if not set.
            if selectedDateFormat == nil {
                // Try to find one
                // selectedDateFormat = .mmddyyyy
            }
            
        case .mint:
            // Mint: Date, Description, Original Description, Amount, Transaction Type, Category, Account Name, Labels, Notes
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" } // Signed amount usually
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" } 
            if let idx = findExact("account name") { columnMapping[idx] = "Account" }
            if let idx = findExact("labels") { columnMapping[idx] = "Tags" }
            
        case .monarch:
            // Monarch: Date, Merchant, Category, Account, Original Statement, Notes, Amount
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("merchant") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }
            if let idx = findExact("account") { columnMapping[idx] = "Account" }
            if let idx = findExact("tags") { columnMapping[idx] = "Tags" }

        case .chase:
            // Chase: Transaction Date, Post Date, Description, Category, Type, Amount, Memo
            if let idx = findExact("transaction date") ?? findExact("posting date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("memo") ?? findExact("details") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") ?? findExact("type") { columnMapping[idx] = "Category" }

        case .bankOfAmerica:
            // BofA: Posted Date, Reference Number, Payee, Address, Amount
            if let idx = findExact("posted date") ?? findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("payee") ?? findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }

        case .wellsFargo:
            // Wells Fargo: Date, Amount, *, *, Name, Memo
            if let idx = findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("name") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }

        case .citi:
            // Citi: Status, Date, Description, Debit, Credit
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .capitalOne:
            // Capital One: Transaction Date, Posted Date, Card No., Description, Category, Debit, Credit
            if let idx = findExact("transaction date") ?? findExact("posted date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .discover:
            // Discover: Trans. Date, Post Date, Description, Amount, Category
            if let idx = findExact("trans. date") ?? findExact("post date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }

        case .amex:
            // Amex: Date, Description, Amount, Extended Details, Appears On Your Statement As, Address, City/State, Zip Code, Country, Reference, Category
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("extended details") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }

        case .paypal:
            // PayPal: Date, Time, Time Zone, Name, Type, Status, Currency, Gross, Fee, Net, From Email Address, To Email Address, Transaction ID, Item Title, Item ID, Reference Txn ID, Receipt ID, Balance
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") { columnMapping[idx] = "Payee" }
            if let idx = findExact("net") ?? findExact("gross") { columnMapping[idx] = "Amount" }
            if let idx = findExact("item title") ?? findExact("type") { columnMapping[idx] = "Memo" }

        case .venmo:
            // Venmo: ID, Datetime, Type, Status, Note, From, To, Amount (total), Amount (fee), Funding Source, Destination
            if let idx = findExact("datetime") ?? findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("from") ?? findExact("to") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount (total)") ?? findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("note") { columnMapping[idx] = "Memo" }

        case .cashApp:
            // Cash App: Transaction ID, Date, Transaction Type, Currency, Amount, Fee, Net Amount, Asset Type, Asset Price, Asset Amount, Status, Notes, Name, Account
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") { columnMapping[idx] = "Payee" }
            if let idx = findExact("net amount") ?? findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("transaction type") { columnMapping[idx] = "Category" }

        case .rbc:
            // RBC: Account Type, Account Number, Transaction Date, Cheque Number, Description 1, Description 2, CAD$, USD$
            if let idx = findExact("transaction date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description 1") ?? findExact("description 2") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("cad$") ?? findExact("usd$") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }

        case .td:
            // TD: Date, Description, Debit, Credit, Balance
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .scotiabank:
            // Scotiabank: Transaction Date, Institution, Account Number, Transaction Code, Transaction Description, Cheque Number, Transaction Amount
            if let idx = findExact("transaction date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("transaction description") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("transaction amount") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }

        case .bmo:
            // BMO: First Bank Card, Transaction Type, Date Posted, Transaction Amount, Description
            if let idx = findExact("date posted") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("transaction amount") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("transaction type") { columnMapping[idx] = "Memo" }

        case .cibc:
            // CIBC: Date, Description, Withdrawals, Deposits
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("withdrawals") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("deposits") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .nationalBank:
            // National Bank: Date, Description, Debit, Credit, Balance
            if let idx = findExact("date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .tangerine:
            // Tangerine: Date, Transaction, Name, Memo, Amount
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") ?? findExact("transaction") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }

        case .simplii:
            // Simplii: Date, Transaction, Description, Funds Out, Funds In
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findExact("transaction") { columnMapping[idx] = "Payee" }
            if let idx = findExact("funds out") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("funds in") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .wealthsimple:
            // Wealthsimple: Date, Account, Type, Description, Reference #, Amount (CAD), Amount (USD)
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findExact("type") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount (cad)") ?? findExact("amount (usd)") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("reference #") { columnMapping[idx] = "Memo" }
            if let idx = findExact("account") { columnMapping[idx] = "Account" }

        case .custom:
            // Generic heuristic from before
            if let idx = findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findIndex(containing: "payee") ?? findIndex(containing: "description") ?? findIndex(containing: "name") {
                columnMapping[idx] = "Payee"
            }
            if let idx = findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findIndex(containing: "memo") ?? findIndex(containing: "note") { columnMapping[idx] = "Memo" }
            if let idx = findIndex(containing: "category") { columnMapping[idx] = "Category" }
            if let idx = findExact("account") ?? findExact("account name") ?? findIndex(containing: "account") ?? findIndex(containing: "acct") {
                columnMapping[idx] = "Account"
            }
            if let idx = findIndex(containing: "tag") ?? findIndex(containing: "label") { columnMapping[idx] = "Tags" }
            // Mapping Inflow/Outflow if detected (Generic)
            if let idx = findIndex(containing: "inflow") { columnMapping[idx] = ColumnType.inflow.rawValue }
            if let idx = findIndex(containing: "outflow") { columnMapping[idx] = ColumnType.outflow.rawValue }

            // Escape Budget extended columns (transfers, etc)
            if let idx = findExact("kind") ?? findIndex(containing: "kind") {
                columnMapping[idx] = ColumnType.kind.rawValue
            }
            if let idx = findExact("transfer id") ?? findExact("transferid") ?? findIndex(containing: "transfer id") ?? findIndex(containing: "transferid") {
                columnMapping[idx] = ColumnType.transferID.rawValue
            }
            if let idx = findExact("external transfer label") ?? findIndex(containing: "external transfer") {
                columnMapping[idx] = ColumnType.externalTransferLabel.rawValue
            }
            if let idx = findExact("transfer inbox dismissed") ?? findIndex(containing: "dismiss") {
                columnMapping[idx] = ColumnType.transferInboxDismissed.rawValue
            }
            if let idx = findExact("purchase items") ??
                findExact("purchased items") ??
                findExact("line items") ??
                findIndex(containing: "purchase items") ??
                findIndex(containing: "purchased items") ??
                findIndex(containing: "line items") {
                columnMapping[idx] = ColumnType.purchaseItems.rawValue
            }
        }

        // Cross-template fallbacks (don’t override existing mappings)
        if !columnMapping.values.contains("Payee") {
            if let idx = findExact("description") ?? findIndex(containing: "description") {
                columnMapping[idx] = "Payee"
            }
        }

        if !columnMapping.values.contains("Account") {
            if let idx = findExact("account") ??
                findExact("account name") ??
                findIndex(containing: "account name") ??
                findIndex(containing: "account") ??
                findIndex(containing: "acct") {
                columnMapping[idx] = "Account"
            }
        }
    }

    private func requestImportConfirmation() {
        guard defaultAccount != nil else {
            errorMessage = "Please select a default account for this import."
            return
        }
        showingSignConfirmation = true
    }

    private func attachPurchasedItems(from json: String?, to transaction: Transaction) {
        let decoded = PurchasedItemsCSVCodec.decode(json)
        guard !decoded.isEmpty else { return }

        for (index, payload) in decoded.prefix(TransactionTextLimits.maxPurchasedItemsPerTransaction).enumerated() {
            let name = TransactionTextLimits.normalizedPurchasedItemName(payload.name)
            let price = Decimal(string: payload.price) ?? 0
            let note = TransactionTextLimits.normalizedPurchasedItemNote(payload.note)
            let item = PurchasedItem(
                name: name,
                price: price,
                note: note,
                order: index,
                transaction: transaction,
                isDemoData: transaction.isDemoData
            )
            modelContext.insert(item)
        }
    }

    private func beginImport(signConvention: AmountSignConvention) {
        self.signConvention = signConvention
        startImport(signConvention: signConvention)
    }

	private func startImport(signConvention: AmountSignConvention) {
        guard let url = selectedFileURL else { return }

        if !hasConfiguredImportOptionsThisRun {
            importOptions = ImportProcessingOptions(
                normalizePayee: normalizePayeeOnImport,
                applyAutoRules: applyAutoRulesOnImport,
                detectDuplicates: detectDuplicatesOnImport,
                suggestTransfers: suggestTransfersOnImport,
                saveProcessingHistory: saveProcessingHistory
            )
        }
        
        currentStep = .importing
        importedCount = 0
        isProcessing = true
        importProgress = ImportProgressState(
            title: "Importing",
            phase: .parsing,
            message: "Parsing CSV…",
            current: 0,
            total: nil,
            canCancel: true
        )
        
        let headers = previewRows[headerRowIndex]
        let mapping = columnMapping
        let hIndex = headerRowIndex
        
        
        let dateFormat = selectedDateFormat
        let sign = signConvention
        
        // Use detached task to avoid running on MainActor (which causes UI freeze and 'no async' warning)
        importTask = Task.detached(priority: .userInitiated) {
            do {
                var localBatch: [ImportedTransaction] = []

                // Stream full file
                var rowIndex = -1
                var parsedCount = 0
                let maxRows = 1_000_000 // 1 million row limit to prevent memory exhaustion
                for try await row in RobustCSVParser.parse(url: url) {
                    if Task.isCancelled { throw CancellationError() }
                    rowIndex += 1
                    // Skip rows before data
                    if rowIndex <= hIndex { continue }

                    // Protect against unbounded row count
                    if parsedCount >= maxRows {
                        throw NSError(domain: "Import", code: 3, userInfo: [NSLocalizedDescriptionKey: "File exceeds maximum of \(maxRows) rows"])
                    }

                    if let data = self.extractTransactionData(from: row, headers: headers, columnMapping: mapping, dateFormatOption: dateFormat, signConvention: sign) {
                         localBatch.append(data)
                         parsedCount += 1
                         if parsedCount % 50 == 0 {
                             let count = parsedCount
                             await MainActor.run {
                                 self.importProgress?.phase = .parsing
                                 self.importProgress?.current = count
                                 self.importProgress?.message = "Parsing CSV…"
                                 self.importedCount = count
                             }
                         }
                    }
                }
                
                // Done parsing, now check duplicates on MainActor (requires modelContext access usually, or we fetch first)
						await MainActor.run { [localBatch] in
							if self.importOptions.normalizePayee {
								self.stagedTransactions = localBatch.map { tx in
									var updated = tx
									let raw = tx.rawPayee ?? tx.payee
									updated.payee = PayeeNormalizer.normalizeDisplay(raw)
									return updated
								}
							} else {
								self.stagedTransactions = localBatch
							}
						self.importProgress?.phase = .preparing
						self.importProgress?.current = localBatch.count
						self.importProgress?.message = "Preparing account/category/tag mapping…"
						self.prepareAccountMappingOrContinue()
						self.isProcessing = false
						self.importProgress = nil
					}
                
                // Clean up file
                try? FileManager.default.removeItem(at: url)
                
            } catch is CancellationError {
                // Clean up temp file on cancellation
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.isProcessing = false
                    self.importProgress = nil
                }
            } catch {
                // Clean up temp file on error
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.errorMessage = (error as NSError).localizedDescription
                    self.currentStep = .preview
                    self.isProcessing = false
                    self.importProgress = nil
                }
            }
        }
    }

	    private func prepareAccountMappingOrContinue() {
	        let allRaw = Set(
	            stagedTransactions
	                .compactMap { $0.rawAccount?.trimmingCharacters(in: .whitespacesAndNewlines) }
	                .filter { !$0.isEmpty }
	        )
	        let sorted = allRaw.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

	        guard !sorted.isEmpty else {
	            prepareCategoryMapping()
	            return
	        }

	        importedAccounts = sorted
	        currentStep = .mapAccounts

	        // Auto-map when the imported name matches an existing account name.
	        for raw in sorted {
	            if let match = accounts.first(where: { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	                accountMapping[raw] = match
	            }
	        }
	    }

	    private func prepareCategoryMapping() {
	        let allRaw = Set(stagedTransactions.compactMap { $0.rawCategory })
	        let sorted = allRaw.sorted()

	        guard !sorted.isEmpty else {
	            // No categories to map, proceed to tags (or review)
	            prepareTagMappingOrReview()
	            return
	        }

	        importedCategories = sorted
	        currentStep = .mapCategories

	        // Fetch existing data for UI
	        allCategories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
	        allGroups = (try? modelContext.fetch(FetchDescriptor<CategoryGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []

	        // Auto-map if names match exactly
	        for raw in sorted {
	            if let match = allCategories.first(where: { $0.name.lowercased() == raw.lowercased() }) {
	                categoryMapping[raw] = match
	            }
	        }
	    }

	    private func prepareTagMappingOrReview() {
	        let allRaw = Set(stagedTransactions.flatMap { $0.rawTags })
	        let sorted = allRaw.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

		        guard !sorted.isEmpty else {
		            checkForDuplicates()
	                if importOptions.suggestTransfers {
	                    refreshTransferSuggestions()
	                } else {
	                    transferSuggestions = []
	                    selectedTransferSuggestionIDs = []
	                }
		            currentStep = .review
		            return
		        }

        importedTags = sorted
        currentStep = .mapTags

        allTransactionTags = (try? modelContext.fetch(FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\.name)]))) ?? []

        for raw in sorted {
            if let match = allTransactionTags.first(where: { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                tagMapping[raw] = match
            }
        }
    }

    private func checkForDuplicates() {
        guard !stagedTransactions.isEmpty else { return }
        guard importOptions.detectDuplicates else {
            stagedTransactions = stagedTransactions.map { tx in
                var updated = tx
                updated.isDuplicate = false
                updated.isSelected = true
                updated.duplicateReason = nil
                return updated
            }
            return
        }
        
        // Find date range
        let dates = stagedTransactions.map { $0.date }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return }
        
        // Fetch existing
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.date >= minDate && t.date <= maxDate
            }
        )
        
        guard let existing = try? modelContext.fetch(descriptor) else { return }

        // Mark duplicates with improved matching logic
        var newStaged: [ImportedTransaction] = []
        let config = TransactionDeduper.Config(useNormalizedPayee: importOptions.normalizePayee, similarityThreshold: 0.85)

        for var tx in stagedTransactions {
            var matchReason: String?
            let isDup = existing.contains { ex in
                let result = TransactionDeduper.evaluate(imported: tx, existing: ex, config: config)
                if result.isDuplicate {
                    matchReason = result.reason
                    return true
                }
                return false
            }

            if isDup {
                tx.isDuplicate = true
                tx.isSelected = false // Default unchecked for duplicates
                tx.duplicateReason = matchReason
            } else {
                tx.isDuplicate = false
                tx.isSelected = true
                tx.duplicateReason = nil
            }
            newStaged.append(tx)
        }

        self.stagedTransactions = newStaged
    }

    private func accountNameForImported(_ transaction: ImportedTransaction) -> String {
        resolveAccount(for: transaction)?.name ?? defaultAccount?.name ?? "Default"
    }

    private func refreshTransferSuggestions() {
        transferSuggestionCount = stagedTransactions.compactMap(\.transferID).count / 2
        let previousSelection = selectedTransferSuggestionIDs

        let config = ImportTransferSuggester.Config(maxDaysApart: 3, maxSuggestions: 60, minScore: 0.70)
        transferSuggestions = ImportTransferSuggester.suggest(
            transactions: stagedTransactions,
            config: config,
            eligible: { tx in
                tx.isSelected &&
                !tx.isDuplicate &&
                tx.kind == .standard &&
                tx.transferID == nil &&
                tx.amount != 0 &&
                resolveAccount(for: tx) != nil
            },
            accountIDFor: { tx in
                resolveAccount(for: tx)?.persistentModelID
            },
            transferishHintFor: { tx in
                if let raw = tx.rawCategory, let mapped = categoryMapping[raw], mapped.group?.type == .transfer {
                    return true
                }
                return tx.rawCategory == nil
            }
        )

        // Safety: never auto-select transfer suggestions.
        // Keep only selections that still exist after refresh.
        let validIDs = Set(transferSuggestions.map(\.id))
        selectedTransferSuggestionIDs = previousSelection.intersection(validIDs)
    }

    private func linkSelectedTransferSuggestions() {
        var linkedPairs = 0

        let suggestionsToLink = transferSuggestions.filter { selectedTransferSuggestionIDs.contains($0.id) }
        guard !suggestionsToLink.isEmpty else { return }

        for suggestion in suggestionsToLink {
            guard let outflowIndex = stagedTransactions.firstIndex(where: { $0.id == suggestion.outflowID }) else { continue }
            guard let inflowIndex = stagedTransactions.firstIndex(where: { $0.id == suggestion.inflowID }) else { continue }

            guard stagedTransactions[outflowIndex].transferID == nil,
                  stagedTransactions[inflowIndex].transferID == nil else { continue }
            guard stagedTransactions[outflowIndex].kind == .standard,
                  stagedTransactions[inflowIndex].kind == .standard else { continue }

            let id = UUID()
            stagedTransactions[outflowIndex].kind = .transfer
            stagedTransactions[outflowIndex].transferID = id
            stagedTransactions[outflowIndex].isSelected = true

            stagedTransactions[inflowIndex].kind = .transfer
            stagedTransactions[inflowIndex].transferID = id
            stagedTransactions[inflowIndex].isSelected = true

            linkedPairs += 1
        }

        transferSuggestionCount += linkedPairs
        refreshTransferSuggestions()
    }

    private func unlinkTransfer(id: UUID) {
        for index in stagedTransactions.indices {
            if stagedTransactions[index].transferID == id {
                stagedTransactions[index].kind = .standard
                stagedTransactions[index].transferID = nil
            }
        }
        refreshTransferSuggestions()
    }
    
    private func performFinalImport() {
        let toImport = stagedTransactions.filter { $0.isSelected }
        guard let fallbackAccount = defaultAccount else {
            errorMessage = "Please select a default account for this import."
            currentStep = .preview
            return
        }

        isProcessing = true
        importProgress = ImportProgressState(
            title: "Importing",
            phase: .saving,
            message: "Saving transactions…",
            current: 0,
            total: toImport.count,
            canCancel: true
        )

		    importTask?.cancel()
		    importTask = Task { @MainActor in
                TransactionStatsUpdateCoordinator.beginDeferringUpdates()
                TransactionStatsUpdateCoordinator.markNeedsFullRebuild()
                defer {
                    TransactionStatsUpdateCoordinator.endDeferringUpdates()
                    DataChangeTracker.bump()
                }

		            var tagCache: [String: TransactionTag] = Dictionary(uniqueKeysWithValues: allTransactionTags.map { ($0.name.lowercased(), $0) })

	                var importedTransactions: [Transaction] = []
	                importedTransactions.reserveCapacity(toImport.count)
                var originalPayeeByTransactionID: [PersistentIdentifier: String] = [:]
                originalPayeeByTransactionID.reserveCapacity(min(2048, toImport.count))

            // Capture summary details for the notification.
            let fileName = selectedFileURL?.lastPathComponent ?? "CSV"
            let totalFound = stagedTransactions.count
            let duplicatesFound = stagedTransactions.filter { $0.isDuplicate }.count
            let duplicatesImported = toImport.filter { $0.isDuplicate }.count
            let transferPairsLinked = Set(toImport.filter { $0.kind == .transfer }.compactMap(\.transferID)).count
            let accountsUsedCount: Int = {
                var ids = Set<PersistentIdentifier>()
                ids.reserveCapacity(4)
                for tx in toImport {
                    let account = resolveAccount(for: tx) ?? fallbackAccount
                    ids.insert(account.persistentModelID)
                }
                return ids.count
            }()

            for (index, txData) in toImport.enumerated() {
                if Task.isCancelled { break }

                var finalCategory: Category? = nil
                if let raw = txData.rawCategory, let mapped = categoryMapping[raw] {
                    // Ensure category has a group - if not, assign to default Expenses group
                    if mapped.group == nil {
                        let expensesGroup = getOrCreateDefaultExpensesGroup()
                        mapped.group = expensesGroup
                    }
                    finalCategory = mapped.group?.type == .transfer ? nil : mapped
                }

                let account = resolveAccount(for: txData) ?? fallbackAccount
                let resolvedTags = resolveImportedTags(txData.rawTags, cache: &tagCache)

	                // Store original payee for rule matching during processing
	                let originalPayee = txData.rawPayee ?? txData.payee
		                let newTx = Transaction(
		                    date: txData.date,
		                    payee: txData.payee,
		                    amount: txData.amount,
		                    memo: TransactionTextLimits.normalizedMemo(txData.memo),
		                    status: txData.status,
		                    kind: txData.kind,
		                    transferID: txData.transferID,
		                    account: account,
		                    category: finalCategory,
		                    tags: resolvedTags.isEmpty ? nil : resolvedTags
			                )
                        newTx.transferInboxDismissed = txData.transferInboxDismissed
                        newTx.externalTransferLabel = txData.externalTransferLabel
				                modelContext.insert(newTx)
                        attachPurchasedItems(from: txData.purchaseItemsJSON, to: newTx)
				                account.balance += newTx.amount
                    importedTransactions.append(newTx)
                    originalPayeeByTransactionID[newTx.persistentModelID] = originalPayee

                // Imported transfer links (suggestions or explicit mapping) always clear category.
                // Never auto-convert to an internal transfer during import unless the user explicitly linked a pair.
                // Also avoid persisting "Transfer" group categories (they get normalized into transfers later).
                if newTx.category?.group?.type == .transfer {
                    newTx.category = nil
                }
                if newTx.kind == .transfer {
                    newTx.category = nil
                }

	                let current = index + 1
	                if current % ImportConstants.progressUpdateInterval == 0 || current == toImport.count {
	                    importProgress?.current = current
	                    importProgress?.message = "Saving transactions…"
	                    await Task.yield()
	                }

                if current % ImportConstants.batchSaveInterval == 0 {
                    guard modelContext.safeSave(context: "ImportDataView.performFinalImport.batchSave", showErrorToUser: false) else {
                        errorMessage = "Import failed while saving transactions. Please try again."
                        isProcessing = false
                        importProgress = nil
                        return
                    }
                    await Task.yield()
                }
            }

	            guard !Task.isCancelled else {
	                isProcessing = false
	                importProgress = nil
	                return
	            }

	            guard modelContext.safeSave(context: "ImportDataView.performFinalImport.finalSave", showErrorToUser: false) else {
	                errorMessage = "Import failed while saving transactions. Please try again."
	                isProcessing = false
	                importProgress = nil
	                return
	            }

                importProgress?.phase = .processing
                importProgress?.message = "Applying rules and cleaning up…"
                importProgress?.current = 0
                importProgress?.total = importedTransactions.count
                await Task.yield()

	                let processingResult = TransactionProcessor.process(
	                    transactions: importedTransactions,
	                    in: modelContext,
	                    source: .import,
	                    originalPayeeByTransactionID: originalPayeeByTransactionID,
                        configOverride: TransactionProcessor.Config(
                            normalizePayee: importOptions.normalizePayee,
                            applyAutoRules: importOptions.applyAutoRules,
                            suggestTransfers: importOptions.suggestTransfers,
                            saveDetailedHistory: importOptions.saveProcessingHistory,
                            maxDetailedTransactions: 250,
                            maxEventsPerTransaction: 8
                        )
	                )

                guard modelContext.safeSave(context: "ImportDataView.performFinalImport.processingSave", showErrorToUser: false) else {
                    errorMessage = "Import failed while processing transactions. Please try again."
                    isProcessing = false
                    importProgress = nil
                    return
                }

	                importProcessingResult = processingResult

                    StatsSanityChecker.checkRecentMonths(in: modelContext, monthsBack: 3, isDemoData: false)

		            // Add a notification for the import result.
			            let summaryParts: [String] = [
			                "Imported \(toImport.count) of \(totalFound)",
		                accountsUsedCount > 1 ? "Accounts: \(accountsUsedCount)" : nil,
		                (importOptions.applyAutoRules && processingResult.summary.transactionsWithRulesApplied > 0) ? "Auto Rules: \(processingResult.summary.transactionsWithRulesApplied)" : nil,
	                    (importOptions.normalizePayee && processingResult.summary.payeesNormalizedCount > 0) ? "Payees: \(processingResult.summary.payeesNormalizedCount) cleaned" : nil,
		                importOptions.suggestTransfers && transferPairsLinked > 0 ? "Transfers: \(transferPairsLinked) pair\(transferPairsLinked == 1 ? "" : "s")" : nil,
	                    (importOptions.suggestTransfers && processingResult.summary.transferSuggestionsInvolvingProcessed > 0) ? "Transfer suggestions: \(processingResult.summary.transferSuggestionsInvolvingProcessed)" : nil,
		                importOptions.detectDuplicates && duplicatesFound > 0 ? "Duplicates: \(duplicatesFound) (imported \(duplicatesImported))" : nil
		            ].compactMap { $0 }

            let note = AppNotification(
                title: "Import Complete",
                message: "\(fileName) • \(summaryParts.joined(separator: " • "))",
                date: Date(),
                type: .success,
                isRead: false,
                isDemoData: fallbackAccount.isDemoData
            )
            InAppNotificationService.post(
                note,
                in: modelContext,
                topic: .importComplete
            )
            await MainActor.run {
                BadgeService.shared.recordImportCompleted(modelContext: modelContext)
            }

            // Log successful import
            SecurityLogger.shared.logDataImport(rowCount: toImport.count, source: selectedImportSource.rawValue)

            importedCount = toImport.count
            importedFileName = fileName
            currentStep = .complete
            isProcessing = false
            importProgress = nil

            cleanupImportedTempFiles()
        }
    }

    private func cleanupImportedTempFiles() {
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        encryptedExportURL = nil
        encryptedExportPassword = ""
        showingEncryptedExportPasswordSheet = false
    }

    private func resolveImportedTags(_ rawTags: [String], cache: inout [String: TransactionTag]) -> [TransactionTag] {
        var result: [TransactionTag] = []

        for raw in rawTags {
            if ignoredImportedTags.contains(raw) { continue }

            if let mapped = tagMapping[raw] {
                if !result.contains(where: { $0.persistentModelID == mapped.persistentModelID }) {
                    result.append(mapped)
                }
                continue
            }

            let key = raw.lowercased()
            if let existing = cache[key] {
                if !result.contains(where: { $0.persistentModelID == existing.persistentModelID }) {
                    result.append(existing)
                }
                continue
            }

            let nextOrder = (allTransactionTags.map(\.order).max() ?? -1) + 1
            let created = TransactionTag(name: raw, colorHex: TagColorPalette.defaultHex(for: appColorMode), order: nextOrder)
            modelContext.insert(created)
            cache[key] = created
            allTransactionTags.append(created)
            result.append(created)
        }

        return result
    }
    private func resolveAccount(for tx: ImportedTransaction) -> Account? {
        guard let raw = tx.rawAccount?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let mapped = accountMapping[raw] {
            return mapped
        }
        return accounts.first { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private func getOrCreateDefaultExpensesGroup() -> CategoryGroup {
        // Try to find an existing Expenses group
        let expenseType = CategoryGroupType.expense.rawValue
        let descriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == expenseType })

        if let existingExpenseGroups = try? modelContext.fetch(descriptor),
           let firstExpenseGroup = existingExpenseGroups.first {
            return firstExpenseGroup
        }

        // No expense groups exist - create a default one
        let maxOrder = allGroups.map { $0.order }.max() ?? -1
        let newGroup = CategoryGroup(name: "Expenses", order: maxOrder + 1, type: .expense)
        modelContext.insert(newGroup)
        allGroups.append(newGroup)
        _ = modelContext.safeSave(context: "ImportDataView.getOrCreateDefaultExpensesGroup", showErrorToUser: false)
        return newGroup
    }

    // TransactionImportData struct removed, using ImportedTransaction from ImportModels.swift

    // Using simple creation logic consistent with old one but handling Inflow/Outflow columns
    nonisolated private func extractTransactionData(from row: [String], headers: [String], columnMapping: [Int: String], dateFormatOption: DateFormatOption?, signConvention: AmountSignConvention) -> ImportedTransaction? {
        guard !row.isEmpty else { return nil }

        var date: Date?
        var payee = ""
        var memo: String?
        var finalAmount: Decimal?
        var inflow: Decimal?
        var outflow: Decimal?
        var rawCategory: String?
        var rawAccount: String?
        var rawTags: [String] = []
        var status: TransactionStatus = .uncleared
        var kind: TransactionKind = .standard
        var transferID: UUID? = nil
        var transferInboxDismissed: Bool = false
        var externalTransferLabel: String? = nil
        var purchaseItemsJSON: String? = nil
        var usedSignedAmount = false
        
        // Unused lookup vars - could be used for categorization heuristics later
        // var _accountName: String?

        for (colIndex, value) in row.enumerated() {
            guard let field = columnMapping[colIndex], field != "skip" else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch field {
            case "Date":
                date = ImportParser.parseDate(from: trimmed, option: dateFormatOption)
            case "Payee":
                payee = trimmed
            case "Memo":
                memo = trimmed.isEmpty ? nil : trimmed
            case "Amount":
                finalAmount = ImportParser.parseAmount(trimmed)
                usedSignedAmount = true
            case "Category":
                 rawCategory = trimmed.isEmpty ? nil : trimmed
            case "Account":
                 rawAccount = trimmed.isEmpty ? nil : trimmed
            case "Tags":
                rawTags.append(contentsOf: ImportParser.parseTags(from: trimmed))
            case "Status":
                if trimmed.lowercased().prefix(1) == "c" { status = .cleared }
                else if trimmed.lowercased().prefix(1) == "r" { status = .reconciled }
            case ColumnType.kind.rawValue:
                let raw = trimmed.lowercased()
                if raw.contains("transfer") { kind = .transfer }
                else if raw.contains("ignored") { kind = .ignored }
                else if raw.contains("adjust") { kind = .adjustment }
                else { kind = .standard }
            case ColumnType.transferID.rawValue:
                if let id = UUID(uuidString: trimmed) {
                    transferID = id
                    kind = .transfer
                }
            case ColumnType.externalTransferLabel.rawValue:
                externalTransferLabel = trimmed.isEmpty ? nil : trimmed
            case ColumnType.transferInboxDismissed.rawValue:
                let raw = trimmed.lowercased()
                transferInboxDismissed = raw == "true" || raw == "1" || raw == "yes" || raw == "y"
            case ColumnType.purchaseItems.rawValue:
                purchaseItemsJSON = trimmed.isEmpty ? nil : trimmed
            case ColumnType.inflow.rawValue: // "Inflow"
                 inflow = ImportParser.parseAmount(trimmed)
            case ColumnType.outflow.rawValue: // "Outflow"
                 outflow = ImportParser.parseAmount(trimmed)
            default: break
            }
        }
        
        // Logic for Amount vs Inflow/Outflow
        if let inc = inflow, let out = outflow {
            // YNAB style: Inflow - Outflow
            finalAmount = inc - out
        } else if let inc = inflow {
             finalAmount = inc
        } else if let out = outflow {
             finalAmount = -out // Outflow is usually positive number in CSV representing expense
        }

        if usedSignedAmount, let value = finalAmount, signConvention == .positiveIsExpense {
            finalAmount = -value
        }
        
        guard let validDate = date, let amount = finalAmount else { return nil }

        let uniqueTags = Array(Set(rawTags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        // Transfers never import with a category; they are linked by Transfer ID.
        if kind == .transfer { rawCategory = nil }

        return ImportedTransaction(
            date: validDate,
            payee: payee,
            rawPayee: payee,
            amount: amount,
            memo: memo,
            rawCategory: rawCategory,
            rawAccount: rawAccount,
            rawTags: uniqueTags,
            status: status,
            kind: kind,
            transferID: transferID,
            transferInboxDismissed: transferInboxDismissed,
            externalTransferLabel: externalTransferLabel,
            purchaseItemsJSON: purchaseItemsJSON
        )
    }
    
    // For Preview (MainActor)
    private func createTransaction(from row: [String], headers: [String], columnMapping: [Int: String], dateFormatOption: DateFormatOption?, signConvention: AmountSignConvention) -> Transaction? {
        guard let data = extractTransactionData(from: row, headers: headers, columnMapping: columnMapping, dateFormatOption: dateFormatOption, signConvention: signConvention) else { return nil }
        return Transaction(date: data.date, payee: data.payee, amount: data.amount, memo: TransactionTextLimits.normalizedMemo(data.memo), status: data.status)
    }
    
}

    // MARK: - Subviews

// Helper for sheet
struct CategoryCreationTarget: Identifiable {
    let id = UUID()
    let rawCategory: String
}

struct TagCreationTarget: Identifiable {
    let id = UUID()
    let rawTag: String
}

struct AccountCreationTarget: Identifiable {
    let id = UUID()
    let rawAccount: String
}

private struct ImportProcessingOptionsSheet: View {
    @Binding var options: ImportProcessingOptions
    let onUseOnce: () -> Void
    let onMakeDefault: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import Processing")
                        .font(.headline)
                    Text("Choose what Escape Budget should do during this import. You can use these options once, or set them as your default for future imports.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

	            Section {
	                Toggle("Clean up payee names", isOn: $options.normalizePayee)
	                Toggle("Apply auto rules", isOn: $options.applyAutoRules)
	                Toggle("Detect duplicates", isOn: $options.detectDuplicates)
	                Toggle("Suggest transfers for review", isOn: $options.suggestTransfers)
	                Toggle("Save processing history", isOn: $options.saveProcessingHistory)
	            } header: {
	                Text("Options")
	            } footer: {
	                Text("Transfers are never auto-linked without your confirmation.")
	            }

            Section("Summary") {
                Text(options.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Before You Import")
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button("Use Once") { onUseOnce() }
                    Button("Make Default") { onMakeDefault() }
                } label: {
                    Text("Continue")
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ColumnMappingRowView: View {
    let header: String
    let colIndex: Int
    @Binding var columnMapping: [Int: String]
    let previewValue: String?
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(header)
                    .font(.headline)
                    .lineLimit(1)
                
                if let val = previewValue {
                    Text("Ex: \(val)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                Button("Skip") { setMapping("skip") }
                Divider()
                Button("Date") { setMapping("Date") }
                Button("Payee") { setMapping("Payee") }
                Button("Amount") { setMapping("Amount") }
                Button("Memo") { setMapping("Memo") }
                Button("Category") { setMapping("Category") }
                Button("Account") { setMapping("Account") }
                Button("Tags") { setMapping("Tags") }
                Button("Kind") { setMapping(ColumnType.kind.rawValue) }
                Button("Transfer ID") { setMapping(ColumnType.transferID.rawValue) }
                Button("External Transfer Label") { setMapping(ColumnType.externalTransferLabel.rawValue) }
                Button("Transfer Inbox Dismissed") { setMapping(ColumnType.transferInboxDismissed.rawValue) }
                Button("Purchase Items") { setMapping(ColumnType.purchaseItems.rawValue) }
                // Inflow/Outflow/Status hidden from manual mapper as per user request
                // They are handled via Templates (e.g. YNAB)
            } label: {
                HStack {
                    Text(currentLabel)
                        .foregroundColor(isMapped ? .white : .primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(isMapped ? .white : .secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isMapped ? AppColors.tint(for: appColorMode) : Color(.systemGray5))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func setMapping(_ val: String) {
        columnMapping[colIndex] = val
    }
    
    private var isMapped: Bool {
        let val = columnMapping[colIndex]
        return val != nil && val != "skip"
    }
    
    private var currentLabel: String {
        columnMapping[colIndex] ?? "Skip"
    }
}

struct PreviewTransactionRow: View {
    let transaction: Transaction
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.payee)
                    .font(.headline)
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: currencyCode))
                .foregroundColor(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
        }
    }
}

// MARK: - Legacy / Utils
// Note: TransactionParser is no longer used.

struct CSVDocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.escapeBudgetEncryptedExport, .commaSeparatedText, .plainText],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: CSVDocumentPicker
        
        init(parent: CSVDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
