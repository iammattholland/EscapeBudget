import Foundation
import SwiftUI
import SwiftData

struct TransfersInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

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
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                    }
                }

                Section {
                    Text("Link transfers to exclude them from income/expense and keep balances accurate. Start with suggested pairs or fix unmatched transfers.")
                        .font(.subheadline)
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
                                HStack(spacing: 12) {
                                    if isSelecting {
                                        Image(systemName: selectedSuggestionIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedSuggestionIDs.contains(suggestion.id) ? AppColors.tint(for: appColorMode) : .secondary)
                                    }

                                    SuggestedTransferRow(
                                        suggestion: suggestion,
                                        modelContext: modelContext,
                                        currencyCode: currencyCode
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
                                        HStack(spacing: 12) {
                                            Image(systemName: selectedUnmatchedIDs.contains(transaction.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedUnmatchedIDs.contains(transaction.persistentModelID) ? AppColors.tint(for: appColorMode) : .secondary)
                                            UnmatchedTransferRow(transaction: transaction, currencyCode: currencyCode)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        TransferMatchPickerView(base: transaction, currencyCode: currencyCode)
                                    } label: {
                                        UnmatchedTransferRow(transaction: transaction, currencyCode: currencyCode)
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
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            dismissSelected()
                        } label: {
                            Text("Dismiss (\(selectedCount))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedCount == 0)

                        Button {
                            linkSelectedSuggestions()
                        } label: {
                            Text("Link (\(selectedSuggestionIDs.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedSuggestionIDs.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isSelecting {
                            Button {
                                selectAllVisible()
                            } label: {
                                Label("Select All", systemImage: "checkmark.circle")
                            }

                            Button {
                                clearSelection()
                            } label: {
                                Label("Clear Selection", systemImage: "xmark.circle")
                            }
                            .disabled(selectedCount == 0)

                            Divider()

                            Button {
                                linkSelectedSuggestions()
                            } label: {
                                Label("Link Selected (\(selectedSuggestionIDs.count))", systemImage: "link")
                            }
                            .disabled(selectedSuggestionIDs.isEmpty)

                            Button(role: .destructive) {
                                dismissSelected()
                            } label: {
                                Label("Dismiss Selected (\(selectedCount))", systemImage: "xmark")
                            }
                            .disabled(selectedCount == 0)

                            Divider()

                            Button {
                                exitSelectionMode()
                            } label: {
                                Label("Done Selecting", systemImage: "checkmark")
                            }
                        } else {
                            Button {
                                showingAmountFilter = true
                            } label: {
                                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            }

                            Button {
                                Task { await reloadSuggestions() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .disabled(isLoadingSuggestions)

                            Divider()

                            Button {
                                enterSelectionMode()
                            } label: {
                                Label("Select Multiple", systemImage: "checklist")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showingClearAllConfirm = true
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(item: $pendingSuggestion) { suggestion in
                NavigationStack {
                    TransferSuggestionConfirmView(
                        suggestion: suggestion,
                        currencyCode: currencyCode,
                        onLinked: { transferID in
                            editTransfer = TransferEditorDestination(id: transferID)
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(base.account?.name ?? "From") → \(match.account?.name ?? "To")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(base.payee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(match.payee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(base.date.formatted(.dateTime.month(.abbreviated).day())) • \(suggestion.daysApart)d apart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(suggestion.amount, format: .currency(code: currencyCode))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()

                    Text("\(Int(min(suggestion.score * 100, 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.account?.name ?? "No Account")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: currencyCode))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
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
                        .foregroundStyle(AppColors.danger(for: appColorMode))
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
                    .buttonStyle(.borderedProminent)
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.account?.name ?? "No Account")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transaction.payee)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: currencyCode))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
