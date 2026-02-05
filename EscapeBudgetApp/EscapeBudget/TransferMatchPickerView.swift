import SwiftUI
import SwiftData

struct TransferMatchPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \Account.name) private var accounts: [Account]

    let base: Transaction
    let currencyCode: String
    let onLinked: ((Transaction) -> Void)?
    let onMarkedUnmatched: (() -> Void)?
    let onConvertedToStandard: (() -> Void)?

    @State private var searchText = ""
    @State private var window: TransferLinker.SearchWindow = .days(7)
    @State private var errorMessage: String?
    @State private var candidates: [(transaction: Transaction, score: Double)] = []
    @State private var isLoadingCandidates = false
    @State private var pendingCandidateID: PersistentIdentifier?
    @State private var showingConfirm = false
    @State private var showingExternalTransferSheet = false
    @State private var externalTransferLabel = ""
    @State private var showingCreateTrackingConfirm = false

    init(
        base: Transaction,
        currencyCode: String,
        onLinked: ((Transaction) -> Void)? = nil,
        onMarkedUnmatched: (() -> Void)? = nil,
        onConvertedToStandard: (() -> Void)? = nil
    ) {
        self.base = base
        self.currencyCode = currencyCode
        self.onLinked = onLinked
        self.onMarkedUnmatched = onMarkedUnmatched
        self.onConvertedToStandard = onConvertedToStandard
    }

    private var matches: [(transaction: Transaction, score: Double)] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return candidates }
        return candidates.filter {
            ($0.transaction.payee.localizedCaseInsensitiveContains(needle)) ||
            (($0.transaction.account?.name.localizedCaseInsensitiveContains(needle)) ?? false)
        }
    }

    private var externalLabelTrimmed: String {
        externalTransferLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingAccountForExternalLabel: Account? {
        let label = externalLabelTrimmed
        guard !label.isEmpty else { return nil }
        return accounts.first(where: { $0.name.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text("Amount")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    Text(base.amount, format: .currency(code: currencyCode))
                        .appSectionTitleText()

                    if let accountName = base.account?.name {
                        Text("Account: \(accountName)")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)

                Picker("Search window", selection: $window) {
                    Text("7d").tag(TransferLinker.SearchWindow.days(7))
                    Text("30d").tag(TransferLinker.SearchWindow.days(30))
                    Text("90d").tag(TransferLinker.SearchWindow.days(90))
                    Text("All").tag(TransferLinker.SearchWindow.all)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Transfer")
            } footer: {
                Text("Pick the matching transaction in the other account. Matches must be the same amount in the opposite direction.")
            }

            Section {
                if isLoadingCandidates {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if matches.isEmpty {
                    ContentUnavailableView(
                        "No Matches Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try widening the search window or search by account name.")
                    )
                    .listRowSeparator(.hidden)

                    HStack {
                        Spacer()
                        Button {
                            showingExternalTransferSheet = true
                        } label: {
                            Label("Mark as External Transfer", systemImage: "arrow.left.arrow.right.circle")
                                .fontWeight(.semibold)
                        }
                        .appPrimaryCTA()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(matches.indices, id: \.self) { index in
                        let match = matches[index]
                        let candidate = match.transaction
                        let score = match.score
                        let isBestMatch = index == 0

                        Button {
                            pendingCandidateID = candidate.persistentModelID
                            showingConfirm = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                    HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                                        Text(candidate.account?.name ?? "No Account")
                                            .appSectionTitleText()
                                        if isBestMatch {
                                            Image(systemName: "star.fill")
                                                .appCaptionText()
                                                .foregroundStyle(.yellow)
                                        }
                                    }
                                    Text(candidate.date, format: .dateTime.month().day().year())
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(min(score, 100)))% match")
                                        .appCaption2Text()
                                        .foregroundStyle(score >= 80 ? .green : score >= 60 ? .orange : .secondary)
                                }
                                Spacer()
                                Text(candidate.amount, format: .currency(code: currencyCode))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            } header: {
                Text("Matches")
            }

            if base.isTransfer, base.transferID == nil {
                Section {
                    Button(role: .destructive) {
                        convertToStandard()
                    } label: {
                        Label("Convert back to standard", systemImage: "arrow.uturn.backward")
                    }
                } footer: {
                    Text("If this isn’t a real transfer, convert it back to a standard transaction and categorize it normally.")
                }
            }
        }
        .navigationTitle("Match Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search accounts or payees")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingExternalTransferSheet) {
            externalTransferSheet
        }
        .alert("Create external account?", isPresented: $showingCreateTrackingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                createTrackingAccountAndLinkTransfer()
            }
        } message: {
            Text("Create an account named “\(externalLabelTrimmed)” to track this external transfer, and link this transfer to it?")
        }
        .navigationDestination(isPresented: $showingConfirm) {
            if let id = pendingCandidateID,
               let candidate = modelContext.model(for: id) as? Transaction {
                TransferMatchConfirmView(
                    base: base,
                    candidate: candidate,
                    currencyCode: currencyCode,
                    onConfirm: {
                        link(candidate)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Transfer",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("That transaction is no longer available.")
                )
            }
        }
        .onChange(of: showingConfirm) { _, newValue in
            if !newValue {
                pendingCandidateID = nil
            }
        }
        .task(id: window) {
            await reloadCandidates()
        }
    }

    @MainActor
    private func reloadCandidates() async {
        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        errorMessage = nil
        let fetchLimit: Int = switch window {
        case .days(let days) where days <= 7: 300
        case .days(let days) where days <= 30: 750
        case .days: 1500
        case .all: 3000
        }

        let rawCandidates = TransferLinker.candidateMatches(for: base, modelContext: modelContext, window: window, fetchLimit: fetchLimit)

        // Score each candidate using the transfer scoring model
        let scoringModel = TransferScoringModel(modelContext: modelContext)
        let learner = TransferPatternLearner(modelContext: modelContext)
        let patterns = learner.fetchReliablePatterns()

        candidates = rawCandidates.map { candidate in
            let features = TransferMatcher.TransferFeatures(transaction1: base, transaction2: candidate)
            let score = scoringModel.scoreMatch(features, patterns: patterns)
            return (transaction: candidate, score: score)
        }
        .sorted { $0.score > $1.score }  // Sort by score descending
    }

    private func link(_ candidate: Transaction) {
        errorMessage = nil
        do {
            try TransferLinker.linkAsTransfer(base: base, match: candidate, modelContext: modelContext)
            onLinked?(candidate)
            dismiss()
        } catch {
            errorMessage = "Couldn’t link transfer. Please try a different match."
        }
    }

    private var externalTransferSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g., Savings at Chase, Mom's account", text: $externalTransferLabel, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                } header: {
                    Text("External Account Label (Optional)")
                } footer: {
                    Text("Specify where this money went if it's to an account you don't track in the app. This will remove it from the Transfers Inbox.")
                }

                if !externalLabelTrimmed.isEmpty {
                    Section {
                        if let match = matchingAccountForExternalLabel {
                            Text("An account named “\(match.name)” already exists.")
                                .appSecondaryBodyText()
                                .foregroundStyle(.secondary)

                            Button {
                                createTrackingAccountAndLinkTransfer(using: match)
                            } label: {
                                Label("Link Transfer to This Account", systemImage: "link")
                            }
                        } else {
                            Button {
                                showingCreateTrackingConfirm = true
                            } label: {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                                    Label("Create External Account", systemImage: "plus.circle")
                                        .fontWeight(.semibold)
                                    Text("Creates an account in Accounts so you can track transfers to/from it.")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("External Account")
                    } footer: {
                        Text("External accounts are useful for institutions you want visibility into without full budgeting.")
                    }
                }
            }
            .navigationTitle("External Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        externalTransferLabel = ""
                        showingExternalTransferSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as External") {
                        markAsExternalTransfer()
                    }
                }
            }
        }
    }

    private func markAsExternalTransfer() {
        errorMessage = nil
        let label = externalLabelTrimmed

        base.transferInboxDismissed = false
        base.externalTransferLabel = label.isEmpty ? "External Account" : label

        guard modelContext.safeSave(context: "TransferMatchPickerView.markAsExternalTransfer") else {
            errorMessage = "Couldn't mark as external transfer."
            return
        }

        TransactionHistoryService.append(
            detail: "Marked as external transfer\(label.isEmpty ? "" : ": \(label)").",
            to: base,
            in: modelContext
        )
        _ = modelContext.safeSave(context: "TransferMatchPickerView.markAsExternalTransfer.history")

        onMarkedUnmatched?()
        externalTransferLabel = ""
        showingExternalTransferSheet = false
        dismiss()
    }

    private func createTrackingAccountAndLinkTransfer(using existing: Account? = nil) {
        errorMessage = nil
        let label = externalLabelTrimmed
        guard !label.isEmpty else { return }
        guard let baseAccount = base.account else {
            errorMessage = "This transaction is missing an account."
            return
        }

        do {
            let targetAccount: Account
            if let existing {
                targetAccount = existing
            } else if let match = matchingAccountForExternalLabel {
                targetAccount = match
            } else {
                let newAccount = Account(
                    name: label,
                    type: .other,
                    balance: 0,
                    notes: "External account",
                    isTrackingOnly: true,
                    isDemoData: base.isDemoData
                )
                modelContext.insert(newAccount)
                targetAccount = newAccount
            }

            if targetAccount.persistentModelID == baseAccount.persistentModelID {
                errorMessage = "Transfers must be between two different accounts."
                return
            }

            let counterpart = Transaction(
                date: base.date,
                payee: base.payee,
                amount: -base.amount,
                memo: base.memo,
                status: base.status,
                kind: .standard,
                transferID: nil,
                account: targetAccount,
                category: nil,
                parentTransaction: nil,
                tags: nil,
                isDemoData: base.isDemoData
            )
            modelContext.insert(counterpart)

            base.externalTransferLabel = nil
            base.transferInboxDismissed = false

            try TransferLinker.linkAsTransfer(base: base, match: counterpart, modelContext: modelContext)
            onLinked?(counterpart)

            externalTransferLabel = ""
            showingExternalTransferSheet = false
            dismiss()
        } catch {
            errorMessage = "Couldn’t create the tracking account transfer. Please try again."
        }
    }

    private func markUnmatched() {
        errorMessage = nil
        do {
            try TransferLinker.markUnmatchedTransfer(base, modelContext: modelContext)
            onMarkedUnmatched?()
            dismiss()
        } catch {
            errorMessage = "Couldn't mark as transfer."
        }
    }

    private func convertToStandard() {
        errorMessage = nil
        do {
            try TransferLinker.convertToStandard(base, modelContext: modelContext)
            onConvertedToStandard?()
            dismiss()
        } catch {
            errorMessage = "Couldn’t convert this transfer."
        }
    }
}

private struct TransferMatchConfirmView: View {
    @Environment(\.dismiss) private var dismiss

    let base: Transaction
    let candidate: Transaction
    let currencyCode: String
    let onConfirm: () -> Void

    var body: some View {
        List {
            Section {
                transferRow(title: "This Transaction", transaction: base)
            }

            Section {
                transferRow(title: "Matching Transaction", transaction: candidate)
            }

            Section {
                Button {
                    onConfirm()
                } label: {
                    Label("Link as Transfer", systemImage: "link")
                        .fontWeight(.semibold)
                }
                .appPrimaryCTA()
            } footer: {
                Text("Confirm these two transactions are the same money movement between accounts. This will remove any budget category and exclude it from income/expense stats.")
            }
        }
        .navigationTitle("Confirm Pair")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func transferRow(title: String, transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
            Text(title)
                .appCaptionStrongText()
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                    Text(transaction.payee)
                        .appSectionTitleText()

                    Text(transaction.account?.name ?? "No Account")
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    if let memo = transaction.memo, !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(memo)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.hairline) {
                    Text(transaction.amount, format: .currency(code: currencyCode))
                        .appSectionTitleText()
                        .monospacedDigit()
                    Text(transaction.date, format: .dateTime.month().day().year())
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
    }
}
