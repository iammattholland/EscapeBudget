import Foundation
import SwiftData
import SwiftUI

/// Coordinates the multi-step CSV import process
@MainActor
@Observable
final class ImportCoordinator {
    // MARK: - Import Flow State

    enum Step {
        case selectFile
        case selectHeader
        case mapColumns
        case preview
        case importing // Parsing phase
        case mapAccounts
        case mapCategories
        case mapTags
        case review // Duplicate check & Review phase
        case complete
    }

    var currentStep: Step = .selectFile

    // MARK: - File & Preview State

    var selectedFileURL: URL?
    var encryptedExportURL: URL?
    var encryptedExportPassword = ""
    var isDecryptingEncryptedExport = false
    var showingEncryptedExportPasswordSheet = false

    var previewRows: [[String]] = []
    var headerRowIndex: Int = 0
    var columnMapping: [Int: String] = [:] // Column index -> field name
    var hasLoadedPreview = false
    var importedFileName: String?

    // MARK: - Import Source & Format

    var selectedImportSource: ImportSource = .custom
    var selectedDateFormat: DateFormatOption?
    var defaultAccount: Account?
    var signConvention: AmountSignConvention?
    var showingSignConfirmation = false

    // MARK: - Import Processing State

    var isProcessing = false
    var errorMessage: String?
    var importTask: Task<Void, Never>?
    var importProgress: ImportProgressState?
    var importedCount = 0

    // MARK: - Staged Data

    var stagedTransactions: [ImportedTransaction] = []
    var importProcessingResult: TransactionProcessor.Result?
    var showingImportProcessingReview = false

    // MARK: - Import Options

    var importOptions = ImportProcessingOptions(
        normalizePayee: true,
        applyAutoRules: true,
        detectDuplicates: true,
        suggestTransfers: true,
        saveProcessingHistory: false
    )

    var showingImportOptionsSheet = false
    var hasConfiguredImportOptionsThisRun = false

    // MARK: - Account Mapping State

    var importedAccounts: [String] = []
    var accountMapping: [String: Account] = [:]

    var unmappedAccounts: [String] {
        importedAccounts.filter { accountMapping[$0] == nil }
    }

    // MARK: - Category Mapping State

    var importedCategories: [String] = []
    var categoryMapping: [String: Category] = [:]
    var allCategories: [Category] = []
    var allGroups: [CategoryGroup] = []

    var unmappedCategories: [String] {
        importedCategories.filter { categoryMapping[$0] == nil }
    }

    // MARK: - Tag Mapping State

    var importedTags: [String] = []
    var ignoredImportedTags: Set<String> = []
    var tagMapping: [String: TransactionTag] = [:]
    var allTransactionTags: [TransactionTag] = []

    var unmappedTags: [String] {
        importedTags.filter { tag in
            !ignoredImportedTags.contains(tag) && tagMapping[tag] == nil
        }
    }

    // MARK: - Transfer Suggestions

    var transferSuggestions: [ImportTransferSuggester.Suggestion] = []
    var selectedTransferSuggestionIDs: Set<String> = []
    var transferSuggestionCount: Int = 0

    // MARK: - Validation

    var canAdvanceFromHeader: Bool {
        headerRowIndex >= 0 && headerRowIndex < previewRows.count
    }

    var canAdvanceToPreview: Bool {
        let mapped = columnMapping.values
        return mapped.contains("Date") && (mapped.contains("Amount") || (mapped.contains("Inflow") || mapped.contains("Outflow")))
    }

    var selectedTransactionsCount: Int {
        stagedTransactions.filter { $0.isSelected }.count
    }

    var duplicatesCount: Int {
        stagedTransactions.filter { $0.isDuplicate }.count
    }

    // MARK: - Wizard Step Indicator

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

    // MARK: - Flow Control

    func reset() {
        currentStep = .selectFile
        selectedFileURL = nil
        previewRows = []
        headerRowIndex = 0
        columnMapping = [:]
        stagedTransactions = []
        importedAccounts = []
        accountMapping = [:]
        importedCategories = []
        categoryMapping = [:]
        importedTags = []
        tagMapping = [:]
        transferSuggestions = []
        selectedTransferSuggestionIDs = []
        transferSuggestionCount = 0
        errorMessage = nil
        isProcessing = false
        importedCount = 0
        hasLoadedPreview = false
        hasConfiguredImportOptionsThisRun = false
    }

    func cancelBackgroundWork() {
        importTask?.cancel()
        importTask = nil
    }

    func cancelImport() {
        cancelBackgroundWork()
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        reset()
    }

    // MARK: - Selection Helpers

    func toggleSelectAll() {
        let anySelected = stagedTransactions.contains { $0.isSelected }
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !anySelected
        }
    }

    func toggleExcludeDuplicates() {
        for index in stagedTransactions.indices {
            if stagedTransactions[index].isDuplicate {
                stagedTransactions[index].isSelected = false
            }
        }
    }

    func selectAllNonDuplicates() {
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !stagedTransactions[index].isDuplicate
        }
    }
}
