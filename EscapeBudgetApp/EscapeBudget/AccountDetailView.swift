import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    let account: Account
        
    @State private var showingImportSheet = false
    @State private var selectedTransaction: Transaction?
    @State private var showingAddTransaction = false
    @State private var showingReconcileSheet = false
    @State private var showingEditAccountSheet = false
    @State private var showingDeleteAccountConfirm = false
    @State private var showingAccountActions = false
    
    var sortedTransactions: [Transaction] {
        account.transactions?.sorted { $0.date > $1.date } ?? []
    }
    
    var body: some View {
        List {
            ForEach(sortedTransactions) { transaction in
                HStack {
                    VStack(alignment: .leading) {
                        Text(displayTitle(for: transaction))
                            .appSectionTitleText()
                        Text(transaction.date, format: .dateTime.month().day())
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(transaction.amount, format: .currency(code: settings.currencyCode))
                        .foregroundStyle(transaction.isTransfer ? .primary : (transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTransaction = transaction
                }
            }
            .onDelete(perform: deleteTransactions)
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAccountActions = true
                } label: {
                    Image(systemName: "ellipsis").appEllipsisIcon()
                }
            }
        }
        .confirmationDialog("Delete \"\(account.name)\"?", isPresented: $showingDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the account and its transactions. Transfer pairs will be removed from both accounts.")
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportView(account: account)
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionFormView(transaction: transaction)
        }
        .sheet(isPresented: $showingAddTransaction) {
            TransactionFormView(defaultAccount: account)
        }
        .sheet(isPresented: $showingReconcileSheet) {
            ReconcileAccountView(preselectedAccount: account)
        }
        .sheet(isPresented: $showingEditAccountSheet) {
            NavigationStack {
                AccountEditSheet(account: account, currencyCode: settings.currencyCode)
            }
        }
        .sheet(isPresented: $showingAccountActions) {
            NavigationStack {
                AccountActionsSheet(
                    onEditAccount: { showingEditAccountSheet = true },
                    onAddTransaction: { showingAddTransaction = true },
                    onAddStatement: { showingImportSheet = true },
                    onReconcile: { showingReconcileSheet = true },
                    onDelete: { showingDeleteAccountConfirm = true }
                )
                .navigationTitle("Account Actions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingAccountActions = false }
                    }
                }
            }
        }
    }
    
    private func deleteTransactions(offsets: IndexSet) {
        withAnimation {
            var processedTransferIDs: Set<UUID> = []

            for index in offsets {
                let transaction = sortedTransactions[index]
                if transaction.isTransfer, let transferID = transaction.transferID {
                    guard !processedTransferIDs.contains(transferID) else { continue }
                    processedTransferIDs.insert(transferID)

                    let id: UUID? = transferID
                    let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
                    let legs = (try? modelContext.fetch(descriptor)) ?? []
                    for leg in legs {
                        if let account = leg.account {
                            account.balance -= leg.amount
                        }
                        modelContext.delete(leg)
                    }
                } else {
                    account.balance -= transaction.amount // Revert balance
                    modelContext.delete(transaction)
                }
            }
        }
    }

    private func deleteAccount() {
        withAnimation {
            // Delete all transactions in this account first; remove transfer pairs from both sides.
            var processedTransferIDs: Set<UUID> = []
            for transaction in sortedTransactions {
                if transaction.isTransfer, let transferID = transaction.transferID {
                    guard !processedTransferIDs.contains(transferID) else { continue }
                    processedTransferIDs.insert(transferID)

                    let id: UUID? = transferID
                    let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
                    let legs = (try? modelContext.fetch(descriptor)) ?? []
                    for leg in legs {
                        if let legAccount = leg.account {
                            legAccount.balance -= leg.amount
                        }
                        modelContext.delete(leg)
                    }
                } else {
                    modelContext.delete(transaction)
                }
            }

            modelContext.delete(account)
            _ = modelContext.safeSave(context: "AccountDetailView.deleteAccount")
        }

        dismiss()
    }

    private func displayTitle(for transaction: Transaction) -> String {
        return transaction.payee
    }
}

private struct AccountActionsSheet: View {
    let onEditAccount: () -> Void
    let onAddTransaction: () -> Void
    let onAddStatement: () -> Void
    let onReconcile: () -> Void
    let onDelete: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onEditAccount()
                } label: {
                    Label("Edit Account", systemImage: "pencil")
                }
            }

            Section("Add") {
                Button {
                    onAddTransaction()
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }

                Button {
                    onAddStatement()
                } label: {
                    Label("Add Statement", systemImage: "square.and.arrow.down")
                }

                Button {
                    onReconcile()
                } label: {
                    Label("Reconcile Account", systemImage: "checkmark.circle")
                }
            }

            Section("Danger") {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct AccountEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings

    let account: Account
    let currencyCode: String

    @State private var name: String = ""
    @State private var type: AccountType = .chequing
    @State private var notes: String = ""
    @State private var isTrackingOnly: Bool = false

    var body: some View {
        Form {
            Section("Details") {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    Text("Name")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    TextField("Enter account name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Picker("Account Type", selection: $type) {
                    ForEach(AccountType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }

                Toggle("External Account", isOn: $isTrackingOnly)

                if isTrackingOnly {
                    Text("Transactions under this account are tracked but not included in any metrics.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 110)
            }
        }
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            name = account.name
            type = account.type
            notes = account.notes ?? ""
            isTrackingOnly = account.isTrackingOnly
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let oldTrackingOnly = account.isTrackingOnly
        account.name = trimmedName
        account.type = type
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        account.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        account.isTrackingOnly = isTrackingOnly

        if oldTrackingOnly != isTrackingOnly {
            TransactionStatsUpdateCoordinator.markNeedsFullRebuild()
        }

        guard modelContext.safeSave(context: "AccountEditSheet.save") else { return }
        dismiss()
    }
}
