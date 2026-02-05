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
    @State private var selectedRuleImpact: RuleImpactSheetItem?

    private struct TransactionSheetItem: Identifiable {
        let id: PersistentIdentifier
        let transaction: Transaction
    }

    private struct RuleImpactSheetItem: Identifiable {
        let id = UUID()
        let ruleName: String
        let rule: AutoRule?
        let transactions: [Transaction]
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

    private func makeRuleImpactItem(ruleName: String) -> RuleImpactSheetItem {
        let descriptor = FetchDescriptor<AutoRule>(
            predicate: #Predicate<AutoRule> { $0.name == ruleName }
        )
        let rule = (try? modelContext.fetch(descriptor))?.first

        let affected = sortedChangedTransactions.filter { tx in
            let events = result.eventsByTransactionID[tx.persistentModelID] ?? []
            return events.contains { event in
                guard event.kind == .ruleApplied else { return false }
                let detail = event.detail ?? ""
                return detail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(ruleName)
            }
        }

        return RuleImpactSheetItem(ruleName: ruleName, rule: rule, transactions: affected)
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

                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                        Text("Options")
                            .appSecondaryBodyStrongText()
                        optionsRow(title: "Payee cleanup", enabled: options.normalizePayee)
                        optionsRow(title: "Auto rules", enabled: options.applyAutoRules)
                        optionsRow(title: "Duplicate detection", enabled: options.detectDuplicates)
                        optionsRow(title: "Transfer suggestions", enabled: options.suggestTransfers)
                        optionsRow(title: "Processing history", enabled: options.saveProcessingHistory)
                    }
                    .padding(.vertical, AppDesign.Theme.Spacing.hairline)
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
                                    Button {
                                        selectedRuleImpact = makeRuleImpactItem(ruleName: item.key)
                                    } label: {
                                        summaryRow(title: item.key, value: "\(item.count)")
                                    }
                                    .buttonStyle(.plain)
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
                                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                                        TransactionRowView(transaction: transaction)

                                        if let events = result.eventsByTransactionID[transaction.persistentModelID], !events.isEmpty {
                                            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                                                ForEach(events) { event in
                                                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                                        HStack(spacing: AppDesign.Theme.Spacing.compact) {
                                                            Image(systemName: iconName(for: event.kind))
                                                                .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                                                            Text(event.title)
                                                                .appFootnoteText()
                                                                .foregroundStyle(.secondary)
                                                        }

                                                        if let detail = event.detail, !detail.isEmpty {
                                                                Text(detail)
                                                                    .appCaptionText()
                                                                    .foregroundStyle(.secondary)
                                                                    .padding(.leading, AppDesign.Theme.Spacing.indentSmall)
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
        .sheet(item: $selectedRuleImpact) { item in
            RuleImpactSheet(
                ruleName: item.ruleName,
                rule: item.rule,
                transactions: item.transactions,
                currencyCode: currencyCode
            )
        }
    }
}

private struct RuleImpactSheet: View {
    let ruleName: String
    let rule: AutoRule?
    let transactions: [Transaction]
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @State private var editingTransaction: Transaction?
    @State private var editingRule: AutoRule?

    var body: some View {
        NavigationStack {
            List {
                Section("Rule") {
                    HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.compact) {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                            Text(ruleName)
                                .appSectionTitleText()
                            if let rule {
                                Text(rule.matchSummary)
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                Text(rule.actionSummary)
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("This rule no longer exists.")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let rule {
                            Button("Edit") {
                                editingRule = rule
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, AppDesign.Theme.Spacing.micro)
                }

                Section("Affected Transactions") {
                    if transactions.isEmpty {
                        ContentUnavailableView(
                            "No transactions found",
                            systemImage: "tray",
                            description: Text("This import summary didn’t include any changed transactions for this rule.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(transactions) { tx in
                            Button {
                                editingTransaction = tx
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                        Text(tx.payee)
                                            .appSecondaryBodyText()
                                        Text(tx.date, format: .dateTime.year().month().day())
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(tx.amount, format: .currency(code: currencyCode))
                                        .appSecondaryBodyText()
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Auto Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $editingTransaction) { tx in
            TransactionFormView(transaction: tx)
        }
        .sheet(item: $editingRule) { rule in
            AutoRuleEditorView(rule: rule)
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
        HStack(spacing: AppDesign.Theme.Spacing.small) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(enabled ? AppDesign.Colors.success(for: appColorMode) : .secondary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .font(AppDesign.Theme.Typography.secondaryBody)
    }

    @ViewBuilder
    private func transferSuggestionRow(_ suggestion: TransferMatcher.Suggestion) -> some View {
        let base = modelContext.model(for: suggestion.baseID) as? Transaction
        let match = modelContext.model(for: suggestion.matchID) as? Transaction

        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
            Text("\(base?.payee ?? "Unknown") ↔︎ \(match?.payee ?? "Unknown")")
                .appSecondaryBodyText()
                .fontWeight(.medium)

            HStack(spacing: AppDesign.Theme.Spacing.compact) {
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
        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
    }
}
