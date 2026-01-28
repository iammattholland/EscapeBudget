import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \Account.name) private var accounts: [Account]
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @Binding var searchText: String
    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var deletingAccount: Account?
    @State private var selectedAccount: Account?
    private let topChrome: AnyView?

    init(searchText: Binding<String>, topChrome: (() -> AnyView)? = nil) {
        self._searchText = searchText
        self.topChrome = topChrome?()
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                List {
                    if let topChrome {
                        topChrome
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    EmptyDataCard(
                        systemImage: "creditcard",
                        title: "No Accounts",
                        message: "Add your first account to begin tracking balances.",
                        actionTitle: "Add Account"
                    ) {
                        showingAddAccount = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .appListTopInset()
                .scrollContentBackground(.hidden)
                .background(ScrollOffsetEmitter(id: "AccountsView.scroll"))
                .coordinateSpace(name: "AccountsView.scroll")
            } else {
                List {
                    if let topChrome {
                        topChrome
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    if filteredAccounts.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    } else {
                        Section {
                            AccountsSummaryCard(
                                count: filteredAccounts.count,
                                totalAssets: totalAssets,
                                totalDebt: totalDebt,
                                netWorth: netWorth,
                                currencyCode: currencyCode
                            )
                            .padding(.top, AppTheme.Spacing.small)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .textCase(nil)

                        ForEach(AccountType.allCases) { type in
                            let typeAccounts = filteredAccounts.filter { $0.type == type }
                            if !typeAccounts.isEmpty {
                                Section(header: Text(type.rawValue)) {
                                    ForEach(typeAccounts) { account in
                                        AccountRow(account: account, currencyCode: currencyCode)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedAccount = account
                                            }
                                            .highPriorityGesture(
                                                LongPressGesture(minimumDuration: 0.35)
                                                    .onEnded { _ in
                                                        Haptics.impact(.medium)
                                                        editingAccount = account
                                                    }
                                            )
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deletingAccount = account
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }

                                            Button {
                                                editingAccount = account
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(AppColors.tint(for: appColorMode))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .appListCompactSpacing()
                .appListTopInset(AppTheme.Spacing.medium)
                .background(ScrollOffsetEmitter(id: "AccountsView.scroll"))
                .coordinateSpace(name: "AccountsView.scroll")
            }
        }
        .navigationDestination(item: $selectedAccount) { account in
            AccountDetailView(account: account)
        }
        .onAppear {
            recomputeBalancesForZeroedAccountsIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        do {
                            try undoRedoManager.undo()
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.undo")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t undo that action. Please try again."
                            )
                        }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!undoRedoManager.canUndo)

                    Button {
                        do {
                            try undoRedoManager.redo()
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.redo")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t redo that action. Please try again."
                            )
                        }
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!undoRedoManager.canRedo)

                    Divider()

                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            NavigationStack {
                AccountEditorSheet(
                    title: "New Account",
                    currencyCode: currencyCode,
                    initialName: "",
                    initialType: .chequing,
                    initialBalance: 0,
                    initialNotes: "",
                    onSave: { name, type, balance, notes in
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes
                        do {
                            try undoRedoManager.execute(
                                AddAccountCommand(
                                    modelContext: modelContext,
                                    name: name,
                                    type: type,
                                    balance: balance,
                                    notes: notesValue
                                )
                            )
                            return true
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.addAccount")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t save the account. Please try again."
                            )
                            return false
                        }
                    },
                    onDelete: nil
                )
            }
        }
        .sheet(item: $editingAccount) { account in
            NavigationStack {
                AccountEditorSheet(
                    title: "Edit Account",
                    currencyCode: currencyCode,
                    initialName: account.name,
                    initialType: account.type,
                    initialBalance: account.balance,
                    initialNotes: account.notes ?? "",
                    onSave: { name, type, balance, notes in
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes
                        do {
                            try undoRedoManager.execute(
                                UpdateAccountCommand(
                                    modelContext: modelContext,
                                    account: account,
                                    newName: name,
                                    newType: type,
                                    newBalance: balance,
                                    newNotes: notesValue
                                )
                            )
                            return true
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.updateAccount")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t save the account. Please try again."
                            )
                            return false
                        }
                    },
                    onDelete: {
                        deletingAccount = account
                    }
                )
            }
        }
        .confirmationDialog(
            deletingAccount == nil ? "" : "Delete \"\(deletingAccount?.name ?? "")\"?",
            isPresented: Binding(
                get: { deletingAccount != nil },
                set: { if !$0 { deletingAccount = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                guard let account = deletingAccount else { return }
                deletingAccount = nil
                do {
                    try undoRedoManager.execute(DeleteAccountCommand(modelContext: modelContext, account: account))
                } catch {
                    modelContext.delete(account)
                    modelContext.safeSave(context: "AccountsView.deleteAccount.fallback")
                }
            }
            Button("Cancel", role: .cancel) { deletingAccount = nil }
        } message: {
            Text("This will remove the account and its transactions from your budget history.")
        }
    }

    @MainActor
    private func recomputeBalancesForZeroedAccountsIfNeeded() {
        var didUpdate = false
        for account in accounts where account.balance == 0 {
            let txs = account.transactions ?? []
            guard !txs.isEmpty else { continue }
            let filtered = txs.filter { transaction in
                if transaction.parentTransaction != nil {
                    return true
                }
                return (transaction.subtransactions ?? []).isEmpty
            }
            let sum = filtered.reduce(Decimal(0)) { $0 + $1.amount }
            if sum != 0 {
                account.balance = sum
                didUpdate = true
            }
        }
        if didUpdate {
            modelContext.safeSave(context: "AccountsView.recomputeBalancesForZeroedAccountsIfNeeded", showErrorToUser: false)
        }
    }

    private var filteredAccounts: [Account] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return accounts }
        return accounts.filter { account in
            account.name.localizedCaseInsensitiveContains(trimmed) ||
            (account.notes?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
            account.type.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var totalAssets: Decimal {
        filteredAccounts.reduce(0) { $0 + max(0, $1.balance) }
    }

    private var totalDebt: Decimal {
        abs(filteredAccounts.reduce(0) { $0 + min(0, $1.balance) })
    }

    private var netWorth: Decimal {
        filteredAccounts.reduce(0) { $0 + $1.balance }
    }
}

private struct AccountsSummaryCard: View {
    let count: Int
    let totalAssets: Decimal
    let totalDebt: Decimal
    let netWorth: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("Overview")
                        .appSectionTitleText()
                    Text("\(count) account\(count == 1 ? "" : "s")")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(netWorth, format: .currency(code: currencyCode))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(netWorth >= 0 ? .primary : AppColors.danger(for: appColorMode))
            }

            HStack(spacing: AppTheme.Spacing.tight) {
                SummaryPill(title: "Assets", value: totalAssets, currencyCode: currencyCode, tint: AppColors.success(for: appColorMode))
                SummaryPill(title: "Debt", value: totalDebt, currencyCode: currencyCode, tint: AppColors.warning(for: appColorMode))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.Radius.small)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.tight)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(AppTheme.Radius.compact)
    }
}

private struct AccountRow: View {
    let account: Account
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: AppTheme.Spacing.tight) {
            ZStack {
                Circle()
                    .fill(account.type.color.opacity(0.18))
                Image(systemName: account.type.icon)
                    .foregroundStyle(account.type.color)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                Text(account.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: AppTheme.Spacing.xSmall) {
                    Text(account.type.rawValue)
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    if account.isTrackingOnly {
                        Text("External")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, AppTheme.Spacing.xSmall)
                            .padding(.vertical, AppTheme.Spacing.hairline)
                            .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.12)))
                            .foregroundStyle(AppColors.warning(for: appColorMode))
                            .lineLimit(1)
                    }

                    if let notes = account.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("•")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(account.balance, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(account.balance >= 0 ? .primary : AppColors.danger(for: appColorMode))
        }
        .padding(.vertical, AppTheme.Spacing.hairline)
    }
}

private struct AccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let currencyCode: String
    let initialName: String
    let initialType: AccountType
    let initialBalance: Decimal
    let initialNotes: String
    let onSave: (String, AccountType, Decimal, String) -> Bool
    let onDelete: (() -> Void)?

    @State private var name: String = ""
    @State private var type: AccountType = .chequing
    @State private var balance: Decimal = 0
    @State private var notes: String = ""

    private func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.currencySymbol ?? code
    }

    var body: some View {
        Form {
            Section("Details") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
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

	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Current Balance")
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
	                    HStack(spacing: AppTheme.Spacing.compact) {
	                        Text(currencySymbol(for: currencyCode))
	                            .appTitleText()
	                            .fontWeight(.semibold)
	                            .foregroundStyle(.secondary)
	                        TextField("", value: $balance, format: .number)
	                            .keyboardType(.decimalPad)
	                    }
	                }
	            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 110)
            }

            if let onDelete {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Account", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if onSave(trimmed, type, balance, notes) {
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            name = initialName
            type = initialType
            balance = initialBalance
            notes = initialNotes
        }
    }
}

#Preview {
    NavigationStack {
        AccountsView(searchText: .constant(""))
            .navigationTitle("Manage Accounts")
    }
    .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
