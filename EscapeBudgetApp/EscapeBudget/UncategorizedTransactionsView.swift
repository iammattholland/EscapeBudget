import SwiftUI
import SwiftData

struct UncategorizedTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    @State private var transactions: [Transaction]
    let currencyCode: String
    let categoryGroups: [CategoryGroup]
    let onDismiss: () -> Void
    @State private var categorizedHistory: [CategorizedChange] = []
    @State private var showingQuickCategorize = false
    @State private var showingSmartCategorize = false
    @State private var showingBulkCategorize = false
    @State private var showingTransferMatch = false
    @State private var transferBaseTransaction: Transaction?
    
    init(transactions: [Transaction], currencyCode: String, categoryGroups: [CategoryGroup], onDismiss: @escaping () -> Void) {
        _transactions = State(initialValue: transactions)
        self.currencyCode = currencyCode
        self.categoryGroups = categoryGroups
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                actionButtons
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.top, AppTheme.Spacing.small)
                    .padding(.bottom, AppTheme.Spacing.xSmall)

                transactionList
            }
            .navigationTitle("Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .fullScreenCover(isPresented: $showingQuickCategorize) {
                QuickCategorizeSessionView(transactions: $transactions)
            }
            .sheet(isPresented: $showingSmartCategorize, onDismiss: {
                // Refresh the transaction list by removing categorized transactions
                transactions.removeAll { $0.category != nil }
            }) {
                SmartCategorizeReviewView(transactions: transactions)
            }
            .sheet(isPresented: $showingBulkCategorize) {
                BulkCategorizeView(
                    transactions: transactions,
                    categoryGroups: categoryGroups,
                    onCategorized: { categorizedTransactions in
                        for transaction in categorizedTransactions {
                            removeTransaction(transaction)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingTransferMatch) {
                NavigationStack {
                    if let base = transferBaseTransaction {
                        TransferMatchPickerView(
                            base: base,
                            currencyCode: currencyCode,
                            onLinked: { candidate in
                                removeTransaction(base)
                                removeTransaction(candidate)
                            },
                            onMarkedUnmatched: {
                                removeTransaction(base)
                            }
                        )
                    }
                }
            }
            .onDisappear {
                onDismiss()
            }
            .background(Color(.systemBackground))
        }
    }

    private var transactionList: some View {
        List {
                    if transactions.isEmpty {
                        EmptyDataCard(
                            systemImage: "checkmark.circle.fill",
                            title: "All transactions categorized",
                            message: "Great job! All your transactions have been assigned to categories."
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(transactions) { transaction in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                                HStack {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                                        Text(transaction.payee)
                                            .appSectionTitleText()
                                        
                                        Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(transaction.amount, format: .currency(code: currencyCode))
                                        .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                                }
                                
                                Menu {
                                    Button {
                                        beginTransferMatch(for: transaction)
                                    } label: {
                                        Label("Transfer", systemImage: "arrow.left.arrow.right")
                                    }

                                    Button {
                                        ignoreTransaction(transaction)
                                    } label: {
                                        Label("Ignore Transaction", systemImage: "nosign")
                                    }

                                    Button("Mark Uncategorized") {
                                        applyCategory(nil, to: transaction)
                                    }
                                    ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                        Section(header: Text(group.name)) {
                                            if let categories = group.categories {
                                                ForEach(categories) { category in
                                                    Button(category.name) {
                                                        applyCategory(category, to: transaction)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Assign Category")
                                        .appCaptionText()
                                        .padding(.horizontal, AppTheme.Spacing.compact)
                                        .padding(.vertical, AppTheme.Spacing.micro)
                                        .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.15)))
                                        .foregroundStyle(AppColors.warning(for: appColorMode))
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                        }
                    }
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !categorizedHistory.isEmpty {
                Button("Undo") {
                    undoLastCategorization()
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
                dismiss()
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            Button {
                showingSmartCategorize = true
            } label: {
                Label("Smart Categorize", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryCTA()
            .disabled(transactions.isEmpty)

            HStack(spacing: AppTheme.Spacing.compact) {
                Button {
                    showingQuickCategorize = true
                } label: {
                    Label("Quick Categorize", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .appSecondaryCTA()
                .disabled(transactions.isEmpty)

                Button {
                    showingBulkCategorize = true
                } label: {
                    Label("Bulk Edit", systemImage: "square.stack.3d.up.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .appSecondaryCTA()
                .disabled(transactions.isEmpty)
            }
        }
    }

    private func applyCategory(_ category: Category?, to transaction: Transaction) {
        categorizedHistory.append(
            CategorizedChange(transaction: transaction, previousCategory: transaction.category)
        )

        let oldSnapshot = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)

        let previousName = transaction.category?.name ?? "Uncategorized"
        transaction.kind = .standard
        transaction.transferID = nil
        transaction.transferInboxDismissed = false
        transaction.category = category

        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

        let newName = category?.name ?? "Uncategorized"
        if previousName != newName {
            TransactionHistoryService.append(
                detail: "Category changed from \(previousName) to \(newName).",
                to: transaction,
                in: modelContext
            )
        }

        if transaction.kind == .standard, transaction.category != nil {
            AutoRulesService(modelContext: modelContext).learnFromCategorization(transaction: transaction, wasAutoDetected: false)
        }

        _ = modelContext.safeSave(context: "UncategorizedTransactionsView.applyCategory", showErrorToUser: false)
        removeTransaction(transaction)
    }

    private func beginTransferMatch(for transaction: Transaction) {
        // Convert standard transaction to transfer
        if transaction.kind == .standard {
            let old = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

            transaction.kind = .transfer
            transaction.category = nil
            transaction.transferID = nil
            transaction.transferInboxDismissed = false

            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

            guard modelContext.safeSave(context: "UncategorizedTransactionsView.beginTransferMatch") else {
                return
            }
        }

        transferBaseTransaction = transaction
        showingTransferMatch = true
    }

    private func ignoreTransaction(_ transaction: Transaction) {
        let old = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

        transaction.kind = .ignored
        transaction.category = nil
        transaction.transferID = nil
        transaction.transferInboxDismissed = false
        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
        modelContext.safeSave(context: "UncategorizedTransactionsView.ignoreTransaction", showErrorToUser: false)
        removeTransaction(transaction)
    }
    
    private func removeTransaction(_ transaction: Transaction) {
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions.remove(at: index)
        }
    }
    
    private func undoLastCategorization() {
        guard let last = categorizedHistory.popLast() else { return }
        last.transaction.category = last.previousCategory
        transactions.insert(last.transaction, at: 0)
    }
}

private struct CategorizedChange: Identifiable {
    let id = UUID()
    let transaction: Transaction
    let previousCategory: Category?
    
    init(transaction: Transaction, previousCategory: Category?) {
        self.transaction = transaction
        self.previousCategory = previousCategory
    }
}
