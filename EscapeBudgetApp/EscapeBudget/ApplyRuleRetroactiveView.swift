import SwiftUI
import SwiftData

struct ApplyRuleRetroactiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    let rule: AutoRule

    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var searchText: String = ""
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var applyProgress: OperationProgressState? = nil

    private var matchingTransactions: [Transaction] {
        let base = allTransactions.filter { tx in
            tx.kind == .standard &&
            rule.matches(payee: tx.payee, account: tx.account, amount: tx.amount)
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }

        return base.filter { TransactionQueryService.matchesSearch($0, query: needle) }
    }

    private var selectedCount: Int {
        selectedIDs.count
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.danger(for: appColorMode))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text("Rule")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    Text(rule.name)
                        .appSectionTitleText()
                    Text(rule.matchSummary)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, AppTheme.Spacing.micro)
            }

            Section {
                HStack(spacing: AppTheme.Spacing.tight) {
                    Button("Select All") {
                        selectedIDs = Set(matchingTransactions.map(\.persistentModelID))
                    }
                    .disabled(matchingTransactions.isEmpty)

                    Button("Clear") {
                        selectedIDs.removeAll()
                    }
                    .disabled(selectedIDs.isEmpty)

                    Spacer()

                    Text("\(selectedCount) selected")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transactions") {
                if matchingTransactions.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty ? "No existing transactions match this rule yet." : "No matches for your search.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(matchingTransactions) { tx in
                        Button {
                            toggle(tx)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.tight) {
                                Image(systemName: selectedIDs.contains(tx.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(tx.persistentModelID) ? AppColors.tint(for: appColorMode) : Color.secondary)

                                VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                                    Text(tx.payee)
                                        .appSectionTitleText()
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: AppTheme.Spacing.xSmall) {
                                        Text(tx.account?.name ?? "No Account")
                                        Text("•")
                                        Text(tx.date, format: .dateTime.year().month().day())
                                    }
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppTheme.Spacing.hairline) {
                                    Text(tx.amount, format: .currency(code: currencyCode))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                    Text(tx.category?.name ?? "Uncategorized")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Apply Previous")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search payee, account, memo, category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isApplying ? "Applying…" : "Apply") {
                    applySelected()
                }
                .disabled(isApplying || selectedIDs.isEmpty)
            }
        }
        .onAppear {
            selectedIDs = Set(matchingTransactions.map(\.persistentModelID))
        }
        .operationProgress(applyProgress)
    }

    private func toggle(_ transaction: Transaction) {
        let id = transaction.persistentModelID
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    @MainActor
    private func applySelected() {
        errorMessage = nil
        isApplying = true

        let service = AutoRulesService(modelContext: modelContext)
        let targets = matchingTransactions.filter { selectedIDs.contains($0.persistentModelID) }
        guard !targets.isEmpty else {
            isApplying = false
            return
        }

        let totalCount = targets.count
        applyProgress = OperationProgressState(
            title: "Applying Rule",
            phase: .processing,
            message: "Processing transactions…",
            current: 0,
            total: totalCount,
            cancellable: false
        )

        Task {
            var processedCount = 0
            for tx in targets {
                _ = service.apply(rule: rule, to: tx, updateStats: true)
                processedCount += 1

                await MainActor.run {
                    applyProgress?.current = processedCount
                    applyProgress?.message = "Processed \(processedCount) of \(totalCount)…"
                }

                // Yield control periodically for UI updates
                if processedCount % 10 == 0 {
                    await Task.yield()
                }
            }

            let saveSuccessful = modelContext.safeSave(
                context: "ApplyRuleRetroactiveView.applySelected",
                userTitle: "Error Applying Rule",
                userMessage: "Couldn't apply the rule. Please try again.",
                showErrorToUser: true
            )

            await MainActor.run {
                isApplying = false
                applyProgress = nil

                if saveSuccessful {
                    InAppNotificationService.post(
                        title: "Rule Applied",
                        message: "Applied “\(rule.name)” to \(totalCount) transaction\(totalCount == 1 ? "" : "s").",
                        type: .success,
                        in: modelContext,
                        topic: .ruleApplied
                    )
                    dismiss()
                }
            }
        }
    }
}
