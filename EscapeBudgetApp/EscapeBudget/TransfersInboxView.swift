import Foundation
import SwiftUI
import SwiftData

struct TransfersInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    
    @Query private var unmatchedTransfers: [Transaction]
    @State private var suggestions: [TransferMatcher.Suggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var errorMessage: String?

    @State private var pendingSuggestion: TransferMatcher.Suggestion?
    @State private var editTransfer: TransferEditorDestination?
    @State private var showingAmountFilter = false
    @State private var amountMinText = ""
    @State private var amountMaxText = ""
    @State private var showingClearAllConfirm = false
    @State private var showingInboxActions = false
    @State private var isSelecting = false
    @State private var selectedSuggestionIDs: Set<String> = []
    @State private var selectedUnmatchedIDs: Set<PersistentIdentifier> = []

    init() {
        let transferRaw = TransactionKind.transfer.rawValue
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        _unmatchedTransfers = Query(
            filter: #Predicate<Transaction> { t in
                t.transferID == nil &&
                t.kindRawValue == transferRaw
            },
            sort: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        self._unmatchedTransfersCutoff = State(initialValue: cutoff)
    }

    @State private var unmatchedTransfersCutoff: Date = .distantPast

    private var filteredSuggestions: [TransferMatcher.Suggestion] {
        suggestions.filter { suggestion in
            amountFilterMatches(suggestion.amount)
        }
    }

    private var filteredUnmatchedTransfers: [Transaction] {
        unmatchedTransfers.filter { transaction in
            guard transaction.transferInboxDismissed == false else { return false }
            guard transaction.externalTransferLabel == nil else { return false }
            guard transaction.amount != 0 else { return false }
            guard transaction.date >= unmatchedTransfersCutoff else { return false }
            return amountFilterMatches(abs(transaction.amount))
        }
    }

    private var unmatchedTransfersForNotification: [Transaction] {
        unmatchedTransfers.filter { transaction in
            guard transaction.transferInboxDismissed == false else { return false }
            guard transaction.externalTransferLabel == nil else { return false }
            guard transaction.amount != 0 else { return false }
            guard transaction.date >= unmatchedTransfersCutoff else { return false }
            return true
        }
    }

    private var selectedSuggestions: [TransferMatcher.Suggestion] {
        filteredSuggestions.filter { selectedSuggestionIDs.contains($0.id) }
    }

    private var selectedUnmatchedTransfers: [Transaction] {
        filteredUnmatchedTransfers.filter { selectedUnmatchedIDs.contains($0.persistentModelID) }
    }

    private var selectedCount: Int {
        selectedSuggestionIDs.count + selectedUnmatchedIDs.count
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                    }
                }

                Section {
                    Text("Link transfers to exclude them from income/expense and keep balances accurate. Start with suggested pairs or fix unmatched transfers.")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                }

                Section {
                    if isLoadingSuggestions {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if filteredSuggestions.isEmpty {
                        ContentUnavailableView(
                            "No Suggestions",
                            systemImage: "sparkles",
                            description: Text("Try again after importing more transactions, or match a transfer manually.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredSuggestions) { suggestion in
                            Button {
                                if isSelecting {
                                    toggleSelection(for: suggestion)
                                } else {
                                    pendingSuggestion = suggestion
                                }
                            } label: {
                                HStack(spacing: AppDesign.Theme.Spacing.tight) {
                                    if isSelecting {
                                        Image(systemName: selectedSuggestionIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedSuggestionIDs.contains(suggestion.id) ? AppDesign.Colors.tint(for: appColorMode) : .secondary)
                                    }

                                    SuggestedTransferRow(
                                        suggestion: suggestion,
                                        modelContext: modelContext,
                                        currencyCode: settings.currencyCode
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        dismissSuggestion(suggestion)
                                    } label: {
                                        Label("Dismiss", systemImage: "xmark")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Suggested Transfers")
                } footer: {
                    Text("Suggestions are based on opposite amounts, account differences, and date proximity.")
                }

                Section {
                    if filteredUnmatchedTransfers.isEmpty {
                        Text("No unmatched transfers.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredUnmatchedTransfers) { transaction in
                            Group {
                                if isSelecting {
                                    Button {
                                        toggleSelection(for: transaction)
                                    } label: {
                                        HStack(spacing: AppDesign.Theme.Spacing.tight) {
                                            Image(systemName: selectedUnmatchedIDs.contains(transaction.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedUnmatchedIDs.contains(transaction.persistentModelID) ? AppDesign.Colors.tint(for: appColorMode) : .secondary)
                                            UnmatchedTransferRow(transaction: transaction, currencyCode: settings.currencyCode)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        TransferMatchPickerView(base: transaction, currencyCode: settings.currencyCode)
                                    } label: {
                                        UnmatchedTransferRow(transaction: transaction, currencyCode: settings.currencyCode)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        convertToStandard(transaction)
                                    } label: {
                                        Label("Standard", systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Unmatched Transfers")
                } footer: {
                    Text("These are marked as transfers but aren’t linked to the matching transaction yet.")
                }
            }
            .navigationTitle("Transfers")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    HStack(spacing: AppDesign.Theme.Spacing.tight) {
                        Button(role: .destructive) {
                            dismissSelected()
                        } label: {
                            Text("Dismiss (\(selectedCount))")
                                .frame(maxWidth: .infinity)
                        }
                        .appSecondaryCTA()
                        .disabled(selectedCount == 0)

                        Button {
                            linkSelectedSuggestions()
                        } label: {
                            Text("Link (\(selectedSuggestionIDs.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .appPrimaryCTA()
                        .disabled(selectedSuggestionIDs.isEmpty)
                    }
                    .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                    .padding(.top, AppDesign.Theme.Spacing.small)
                    .padding(.bottom, AppDesign.Theme.Spacing.tight)
                    .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInboxActions = true
                    } label: {
                        Image(systemName: "ellipsis").appEllipsisIcon()
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(item: $pendingSuggestion) { suggestion in
                NavigationStack {
                    TransferSuggestionConfirmView(
                        suggestion: suggestion,
                        currencyCode: settings.currencyCode,
                        onLinked: { transferID in
                            editTransfer = TransferEditorDestination(id: transferID)
                            removeSuggestionPair(baseID: suggestion.baseID, matchID: suggestion.matchID)
                            Task { await reloadSuggestions() }
                        }
                    )
                }
            }
            .sheet(item: $editTransfer) { destination in
                TransferFormView(transferID: destination.id)
            }
            .sheet(isPresented: $showingAmountFilter) {
                amountFilterSheet
            }
            .sheet(isPresented: $showingInboxActions) {
                NavigationStack {
                    TransfersInboxActionsSheet(
                        isSelecting: isSelecting,
                        isLoading: isLoadingSuggestions,
                        selectedCount: selectedCount,
                        selectedSuggestionsCount: selectedSuggestionIDs.count,
                        onSelectAll: { selectAllVisible() },
                        onClearSelection: { clearSelection() },
                        onLinkSelected: { linkSelectedSuggestions() },
                        onDismissSelected: { dismissSelected() },
                        onDoneSelecting: { exitSelectionMode() },
                        onFilter: { showingAmountFilter = true },
                        onRefresh: { Task { await reloadSuggestions() } },
                        onSelectMultiple: { enterSelectionMode() },
                        onClearAll: { showingClearAllConfirm = true }
                    )
                    .navigationTitle("Transfers Inbox")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingInboxActions = false }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear Transfers Inbox?",
                isPresented: $showingClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    clearAllInboxItems()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This hides current suggestions and unmatched transfers from the inbox. You can still find and link transfers from the transaction list.")
            }
            .task {
                await reloadSuggestions()
            }
            .onDisappear {
                exitSelectionMode()
            }
        }
    }

	    @MainActor
		    private func reloadSuggestions() async {
		        isLoadingSuggestions = true
		        defer { isLoadingSuggestions = false }
		        errorMessage = nil
		
		        var config = TransferMatcher.Config(lookbackDays: 365, maxDaysApart: 14, limit: 250, minScore: 0.55)
		        // Allow small amount differences (fees/rounding) to catch credit card payments and similar transfers.
		        config.maxAmountDifferenceCents = 200
		        suggestions = TransactionQueryService.transferSuggestions(modelContext: modelContext, config: config)
		        postTransfersInboxNotificationIfNeeded()
		    }

    private func postTransfersInboxNotificationIfNeeded() {
        let suggestedCount = suggestions.count
        let unmatchedCount = unmatchedTransfersForNotification.count
        guard suggestedCount > 0 || unmatchedCount > 0 else { return }

        let dayKey: String = {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let df = DateFormatter()
            df.calendar = calendar
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: today)
        }()

        let messageParts: [String] = [
            suggestedCount > 0 ? "\(suggestedCount) suggested" : nil,
            unmatchedCount > 0 ? "\(unmatchedCount) unmatched" : nil
        ].compactMap { $0 }

        let message = "Transfers need review: \(messageParts.joined(separator: " • "))."

        InAppNotificationService.post(
            title: "Transfers Inbox",
            message: message,
            type: .info,
            in: modelContext,
            topic: .transfersInbox,
            dedupeKey: "transfers.inbox.\(dayKey)"
        )
    }

    private func convertToStandard(_ transaction: Transaction) {
        errorMessage = nil
        do {
            try TransferLinker.convertToStandard(transaction, modelContext: modelContext)
            Task { await reloadSuggestions() }
        } catch {
            errorMessage = "Couldn’t convert this transfer."
        }
    }

    private var isAmountFilterActive: Bool {
        !amountMinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !amountMaxText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func decimalFromInput(_ input: String) -> Decimal? {
        let sanitized = input
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        guard !sanitized.isEmpty else { return nil }
        return Decimal(string: sanitized)
    }

    private func amountFilterMatches(_ amount: Decimal) -> Bool {
        let minValue = decimalFromInput(amountMinText)
        let maxValue = decimalFromInput(amountMaxText)

        if let minValue, amount < minValue { return false }
        if let maxValue, amount > maxValue { return false }
        return true
    }

    private var amountFilterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Min", text: $amountMinText)
                        .keyboardType(.decimalPad)
                    TextField("Max", text: $amountMaxText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Filters suggested and unmatched transfers by absolute amount.")
                }

                Section {
                    Button("Clear Filter") {
                        amountMinText = ""
                        amountMaxText = ""
                    }
                    .disabled(!isAmountFilterActive)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingAmountFilter = false }
                }
            }
        }
        .presentationDetents([.medium])
        .solidPresentationBackground()
    }

    private func dismissSuggestion(_ suggestion: TransferMatcher.Suggestion) {
        errorMessage = nil
        let base = modelContext.model(for: suggestion.baseID) as? Transaction
        let match = modelContext.model(for: suggestion.matchID) as? Transaction
        base?.transferInboxDismissed = true
        match?.transferInboxDismissed = true
        modelContext.safeSave(context: "TransfersInboxView.dismissSuggestionPair")
        Task { await reloadSuggestions() }
    }

    private func enterSelectionMode() {
        errorMessage = nil
        isSelecting = true
        clearSelection()
    }

    private func exitSelectionMode() {
        isSelecting = false
        clearSelection()
    }

    private func clearSelection() {
        selectedSuggestionIDs.removeAll()
        selectedUnmatchedIDs.removeAll()
    }

    private func selectAllVisible() {
        selectedSuggestionIDs = Set(filteredSuggestions.map(\.id))
        selectedUnmatchedIDs = Set(filteredUnmatchedTransfers.map(\.persistentModelID))
    }

    private func toggleSelection(for suggestion: TransferMatcher.Suggestion) {
        if selectedSuggestionIDs.contains(suggestion.id) {
            selectedSuggestionIDs.remove(suggestion.id)
        } else {
            selectedSuggestionIDs.insert(suggestion.id)
        }
    }

    private func toggleSelection(for transaction: Transaction) {
        let id = transaction.persistentModelID
        if selectedUnmatchedIDs.contains(id) {
            selectedUnmatchedIDs.remove(id)
        } else {
            selectedUnmatchedIDs.insert(id)
        }
    }

    private func dismissSelected() {
        errorMessage = nil

        for suggestion in selectedSuggestions {
            (modelContext.model(for: suggestion.baseID) as? Transaction)?.transferInboxDismissed = true
            (modelContext.model(for: suggestion.matchID) as? Transaction)?.transferInboxDismissed = true
        }

        for transfer in selectedUnmatchedTransfers {
            transfer.transferInboxDismissed = true
        }

        modelContext.safeSave(context: "TransfersInboxView.dismissSelected")
        exitSelectionMode()
        Task { await reloadSuggestions() }
    }

    private func linkSelectedSuggestions() {
        errorMessage = nil
        let toLink = selectedSuggestions
        guard !toLink.isEmpty else { return }

        var linked = 0
        var failed = 0

        for suggestion in toLink {
            guard let base = modelContext.model(for: suggestion.baseID) as? Transaction,
                  let match = modelContext.model(for: suggestion.matchID) as? Transaction else {
                failed += 1
                continue
            }
            do {
                try TransferLinker.linkAsTransfer(base: base, match: match, modelContext: modelContext)
                removeSuggestionPair(baseID: suggestion.baseID, matchID: suggestion.matchID)
                linked += 1
            } catch {
                failed += 1
            }
        }

        if failed > 0 {
            errorMessage = linked > 0
                ? "Linked \(linked) transfer pair\(linked == 1 ? "" : "s"). \(failed) couldn’t be linked."
                : "Couldn’t link the selected transfers. Try selecting fewer or refreshing."
        } else {
            errorMessage = nil
        }

        exitSelectionMode()
        Task { await reloadSuggestions() }
    }

    private func removeSuggestionPair(baseID: PersistentIdentifier, matchID: PersistentIdentifier) {
        suggestions.removeAll { suggestion in
            suggestion.baseID == baseID ||
            suggestion.matchID == baseID ||
            suggestion.baseID == matchID ||
            suggestion.matchID == matchID ||
            (suggestion.baseID == baseID && suggestion.matchID == matchID) ||
            (suggestion.baseID == matchID && suggestion.matchID == baseID)
        }
        selectedSuggestionIDs = selectedSuggestionIDs.filter { id in
            suggestions.contains { $0.id == id }
        }
    }

    private func clearAllInboxItems() {
        errorMessage = nil

        for suggestion in suggestions {
            (modelContext.model(for: suggestion.baseID) as? Transaction)?.transferInboxDismissed = true
            (modelContext.model(for: suggestion.matchID) as? Transaction)?.transferInboxDismissed = true
        }

        for transaction in unmatchedTransfers {
            transaction.transferInboxDismissed = true
        }

        modelContext.safeSave(context: "TransfersInboxView.clearAllInboxItems")
        Task { await reloadSuggestions() }
    }
}

private struct TransferEditorDestination: Identifiable, Equatable {
    let id: UUID
}

private struct SuggestedTransferRow: View {
    let suggestion: TransferMatcher.Suggestion
    let modelContext: ModelContext
    let currencyCode: String

    private var base: Transaction? { modelContext.model(for: suggestion.baseID) as? Transaction }
    private var match: Transaction? { modelContext.model(for: suggestion.matchID) as? Transaction }

    var body: some View {
        if let base, let match {
            HStack(spacing: AppDesign.Theme.Spacing.tight) {
	                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.nano) {
	                        Text("\(base.account?.name ?? "From") → \(match.account?.name ?? "To")")
	                            .appSecondaryBodyText()
	                            .fontWeight(.semibold)
                            .lineLimit(1)

                    Text(base.payee)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(match.payee)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(base.date.formatted(.dateTime.month(.abbreviated).day())) • \(suggestion.daysApart)d apart")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                    VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.hairline) {
                        Text(suggestion.amount, format: .currency(code: currencyCode))
                            .appSecondaryBodyText()
                            .fontWeight(.semibold)
                            .monospacedDigit()

                    Text("\(Int(min(suggestion.score * 100, 100).rounded()))%")
                        .appCaption2Text()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, AppDesign.Theme.Spacing.micro)
        } else {
            Text("Transfer")
                .foregroundStyle(.secondary)
        }
    }
}

private struct UnmatchedTransferRow: View {
    let transaction: Transaction
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.nano) {
	                Text(transaction.account?.name ?? "No Account")
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: currencyCode))
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : AppDesign.Colors.danger(for: appColorMode))
                .monospacedDigit()
        }
        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
    }
}

private struct TransferSuggestionConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    let suggestion: TransferMatcher.Suggestion
    let currencyCode: String
    let onLinked: (UUID) -> Void

    @State private var errorMessage: String?

    private var base: Transaction? { modelContext.model(for: suggestion.baseID) as? Transaction }
    private var match: Transaction? { modelContext.model(for: suggestion.matchID) as? Transaction }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                }
            }

            if let base, let match {
                Section {
                    TransferTransactionRow(transaction: base, currencyCode: currencyCode)
                    TransferTransactionRow(transaction: match, currencyCode: currencyCode)
                } header: {
                    Text("This looks like a transfer")
                } footer: {
                    Text("These transactions have opposite amounts and are close in time. Linking will remove any budget category and exclude them from income/expense stats.")
                }

                Section {
                    Button {
                        link(base: base, match: match)
                    } label: {
                        Label("Link as Transfer", systemImage: "link")
                            .fontWeight(.semibold)
                    }
                    .appPrimaryCTA()
                }
            } else {
                ContentUnavailableView(
                    "Transfer",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("One of these transactions is no longer available.")
                )
            }
        }
        .navigationTitle("Confirm Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func link(base: Transaction, match: Transaction) {
        errorMessage = nil
        do {
            try TransferLinker.linkAsTransfer(base: base, match: match, modelContext: modelContext)
            if let id = base.transferID ?? match.transferID {
                onLinked(id)
            }
            dismiss()
        } catch {
            errorMessage = "Couldn’t link transfer. Please try a different match."
        }
    }
}

private struct TransferTransactionRow: View {
    let transaction: Transaction
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.nano) {
	                Text(transaction.account?.name ?? "No Account")
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                Text(transaction.payee)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: settings.currencyCode))
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : AppDesign.Colors.danger(for: appColorMode))
                .monospacedDigit()
        }
        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
    }
}

private struct TransfersInboxActionsSheet: View {
    let isSelecting: Bool
    let isLoading: Bool
    let selectedCount: Int
    let selectedSuggestionsCount: Int
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onLinkSelected: () -> Void
    let onDismissSelected: () -> Void
    let onDoneSelecting: () -> Void
    let onFilter: () -> Void
    let onRefresh: () -> Void
    let onSelectMultiple: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        List {
            if isSelecting {
                Section("Selection") {
                    Button {
                        onSelectAll()
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle")
                    }

                    Button {
                        onClearSelection()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .disabled(selectedCount == 0)

                    Button {
                        onLinkSelected()
                    } label: {
                        Label("Link Selected (\(selectedSuggestionsCount))", systemImage: "link")
                    }
                    .disabled(selectedSuggestionsCount == 0)

                    Button(role: .destructive) {
                        onDismissSelected()
                    } label: {
                        Label("Dismiss Selected (\(selectedCount))", systemImage: "xmark")
                    }
                    .disabled(selectedCount == 0)

                    Button {
                        onDoneSelecting()
                    } label: {
                        Label("Done Selecting", systemImage: "checkmark")
                    }
                }
            } else {
                Section("Actions") {
                    Button {
                        onFilter()
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button {
                        onSelectMultiple()
                    } label: {
                        Label("Select Multiple", systemImage: "checklist")
                    }
                }

                Section("Manage") {
                    Button(role: .destructive) {
                        onClearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
        }
    }
}
