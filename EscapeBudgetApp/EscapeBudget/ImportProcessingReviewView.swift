import SwiftUI
import SwiftData

struct ImportProcessingReviewView: View {
    let result: TransactionProcessor.Result
    let fileName: String?
    let options: ImportProcessingOptions

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var editingTransaction: TransactionSheetItem?

    private struct TransactionSheetItem: Identifiable {
        let id: PersistentIdentifier
        let transaction: Transaction
    }

    private var sortedChangedTransactions: [Transaction] {
        result.changedTransactions.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            return lhs.payee < rhs.payee
        }
    }

    private struct AggregatedItem: Identifiable {
        let key: String
        let count: Int
        var id: String { key }
    }

    private var payeeCleanupTop: [AggregatedItem] {
        var counts: [String: Int] = [:]
        for (_, events) in result.eventsByTransactionID {
            for event in events where event.kind == .payeeNormalized {
                let detail = (event.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !detail.isEmpty else { continue }
                counts[detail, default: 0] += 1
            }
        }
        return counts
            .map { AggregatedItem(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }

    private var categoryUpdateTop: [AggregatedItem] {
        var counts: [String: Int] = [:]
        var cleared = 0
        for (_, events) in result.eventsByTransactionID {
            for event in events where event.kind == .categoryChanged {
                if event.title == "Category cleared" {
                    cleared += 1
                    continue
                }
                if event.title == "Category updated" {
                    let categoryName = (event.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !categoryName.isEmpty {
                        counts[categoryName, default: 0] += 1
                    }
                }
            }
        }
        var items = counts
            .map { AggregatedItem(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
        if cleared > 0 {
            items.append(AggregatedItem(key: "Category cleared", count: cleared))
        }
        return items
    }

    private var topAutoRules: [AggregatedItem] {
        var counts: [String: Int] = [:]
        for (_, events) in result.eventsByTransactionID {
            for event in events where event.kind == .ruleApplied {
                let detail = (event.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !detail.isEmpty else { continue }
                let rules = detail
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for rule in rules {
                    counts[rule, default: 0] += 1
                }
            }
        }
        return counts
            .map { AggregatedItem(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }

    private var transferSuggestionCounts: (high: Int, medium: Int, low: Int) {
        var high = 0
        var medium = 0
        var low = 0
        for suggestion in result.transferSuggestions {
            if suggestion.score >= 0.80 { high += 1 }
            else if suggestion.score >= 0.60 { medium += 1 }
            else { low += 1 }
        }
        return (high, medium, low)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This Import") {
                    summaryRow(title: "File", value: fileName ?? "—")

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Options")
                            .font(.subheadline.weight(.semibold))
                        optionsRow(title: "Payee cleanup", enabled: options.normalizePayee)
                        optionsRow(title: "Auto rules", enabled: options.applyAutoRules)
                        optionsRow(title: "Duplicate detection", enabled: options.detectDuplicates)
                        optionsRow(title: "Transfer suggestions", enabled: options.suggestTransfers)
                        optionsRow(title: "Processing history", enabled: options.saveProcessingHistory)
                    }
                    .padding(.vertical, AppTheme.Spacing.hairline)
                }

                Section("Summary") {
                    summaryRow(title: "Processed", value: "\(result.summary.processedCount)")
                    summaryRow(title: "Changed", value: "\(result.summary.changedCount)")

                    if result.summary.payeesNormalizedCount > 0 {
                        summaryRow(title: "Payees cleaned", value: "\(result.summary.payeesNormalizedCount)")
                    }

                    if result.summary.transactionsWithRulesApplied > 0 {
                        summaryRow(title: "Auto rules applied", value: "\(result.summary.transactionsWithRulesApplied) tx (\(result.summary.rulesAppliedCount) rules)")
                    }

                    if result.summary.transferSuggestionsInvolvingProcessed > 0 {
                        summaryRow(title: "Transfer suggestions", value: "\(result.summary.transferSuggestionsInvolvingProcessed)")
                    }

                    if result.summary.changedCount > result.changedTransactions.count, result.changedTransactions.count > 0 {
                        Text("Showing the first \(result.changedTransactions.count) changed transactions for performance.")
                            .appFootnoteText()
                            .foregroundStyle(.secondary)
                    }
                }

                if result.summary.processedCount > 250 && result.eventsByTransactionID.count >= 250 {
                    Section("Note") {
                        Text("For performance, detailed per-transaction event history is shown for the first \(result.eventsByTransactionID.count) transactions. The Highlights section still reflects overall counts.")
                            .appFootnoteText()
                            .foregroundStyle(.secondary)
                    }
                }

                if !payeeCleanupTop.isEmpty || !categoryUpdateTop.isEmpty || !topAutoRules.isEmpty || !result.transferSuggestions.isEmpty {
                    Section("Highlights") {
                        if !payeeCleanupTop.isEmpty {
                            DisclosureGroup("Payee cleanups") {
                                ForEach(payeeCleanupTop) { item in
                                    summaryRow(title: item.key, value: "\(item.count)")
                                }
                            }
                        }

                        if !categoryUpdateTop.isEmpty {
                            DisclosureGroup("Top category updates") {
                                ForEach(categoryUpdateTop) { item in
                                    summaryRow(title: item.key, value: "\(item.count)")
                                }
                            }
                        }

                        if !topAutoRules.isEmpty {
                            DisclosureGroup("Top auto rules") {
                                ForEach(topAutoRules) { item in
                                    summaryRow(title: item.key, value: "\(item.count)")
                                }
                            }
                        }

                        if !result.transferSuggestions.isEmpty {
                            let counts = transferSuggestionCounts
                            DisclosureGroup("Transfer suggestions") {
                                summaryRow(title: "High confidence (≥80%)", value: "\(counts.high)")
                                summaryRow(title: "Medium (60–79%)", value: "\(counts.medium)")
                                if counts.low > 0 {
                                    summaryRow(title: "Low (<60%)", value: "\(counts.low)")
                                }

                                if !result.transferSuggestions.isEmpty {
                                    Divider()
                                    ForEach(Array(result.transferSuggestions.prefix(10).enumerated()), id: \.offset) { _, suggestion in
                                        transferSuggestionRow(suggestion)
                                    }
                                    if result.transferSuggestions.count > 10 {
                                        Text("Showing the top 10 suggestions.")
                                            .appFootnoteText()
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text("Review and link these in Transfers Inbox.")
                                    .appFootnoteText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if result.changedTransactions.isEmpty {
                    Section("Changed Transactions") {
                        Text("No automated changes were made.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Transaction Details") {
                        DisclosureGroup("View changed transactions") {
                            ForEach(sortedChangedTransactions, id: \.persistentModelID) { transaction in
                                Button {
                                    editingTransaction = TransactionSheetItem(
                                        id: transaction.persistentModelID,
                                        transaction: transaction
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                        TransactionRowView(transaction: transaction)

                                        if let events = result.eventsByTransactionID[transaction.persistentModelID], !events.isEmpty {
                                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                                                ForEach(events) { event in
                                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                                                        HStack(spacing: AppTheme.Spacing.compact) {
                                                            Image(systemName: iconName(for: event.kind))
                                                                .foregroundStyle(AppColors.tint(for: appColorMode))
                                                            Text(event.title)
                                                                .appFootnoteText()
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        if let detail = event.detail, !detail.isEmpty {
                                                                Text(detail)
                                                                    .appCaptionText()
                                                                    .foregroundStyle(.secondary)
                                                                    .padding(.leading, AppTheme.Spacing.indentSmall)
                                                            }
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Tip: start with Highlights to review the impact at a glance. Open transaction details only if something looks off.")
                            .appFootnoteText()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingTransaction) { item in
                TransactionFormView(transaction: item.transaction)
            }
        }
    }

    @ViewBuilder
    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func iconName(for kind: TransactionProcessor.EventKind) -> String {
        switch kind {
        case .payeeNormalized:
            return "wand.and.stars"
        case .ruleApplied:
            return "bolt.badge.checkmark"
        case .categoryChanged:
            return "tag"
        case .tagsChanged:
            return "tag.fill"
        case .memoChanged:
            return "note.text"
        case .statusChanged:
            return "checkmark.circle"
        case .transferSuggestion:
            return "arrow.left.arrow.right"
        case .invariantFix:
            return "checkmark.shield"
        }
    }

    private func optionsRow(title: String, enabled: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(enabled ? AppColors.success(for: appColorMode) : .secondary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .font(AppTheme.Typography.secondaryBody)
    }

    @ViewBuilder
    private func transferSuggestionRow(_ suggestion: TransferMatcher.Suggestion) -> some View {
        let base = modelContext.model(for: suggestion.baseID) as? Transaction
        let match = modelContext.model(for: suggestion.matchID) as? Transaction

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text("\(base?.payee ?? "Unknown") ↔︎ \(match?.payee ?? "Unknown")")
                .appSecondaryBodyText()
                .fontWeight(.medium)

            HStack(spacing: AppTheme.Spacing.compact) {
                Text(suggestion.amount, format: .currency(code: currencyCode))
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("\(suggestion.daysApart)d apart")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("score \(String(format: "%.2f", suggestion.score))")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let baseAccount = base?.account?.name, let matchAccount = match?.account?.name {
                Text("\(baseAccount) → \(matchAccount)")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.hairline)
    }
}
