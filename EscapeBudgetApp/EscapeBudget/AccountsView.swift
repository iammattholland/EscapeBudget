import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    @Query(sort: \Account.name) private var accounts: [Account]
    
    @Binding var searchText: String
    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var deletingAccount: Account?
    @State private var selectedAccount: Account?
    @State private var showingAccountsActions = false
    private let topChrome: AnyView?

    init(searchText: Binding<String>, topChrome: (() -> AnyView)? = nil) {
        self._searchText = searchText
        self.topChrome = topChrome?()
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                List {
                    if topChrome != nil {
                        AppChromeListRow(topChrome: topChrome, scrollID: "AccountsView.scroll")
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
                    if topChrome != nil {
                        AppChromeListRow(topChrome: topChrome, scrollID: "AccountsView.scroll")
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
                                currencyCode: settings.currencyCode
                            )
                            .padding(.top, AppDesign.Theme.Spacing.small)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .textCase(nil)

                        ForEach(AccountType.allCases) { type in
                            let typeAccounts = filteredAccounts.filter { $0.type == type }
                            if !typeAccounts.isEmpty {
                                Section(header: Text(type.rawValue)) {
                                    ForEach(typeAccounts) { account in
                                        AccountRow(account: account, currencyCode: settings.currencyCode)
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
                                            .tint(AppDesign.Colors.tint(for: appColorMode))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .appListCompactSpacing()
                .appListTopInset(AppDesign.Theme.Spacing.medium)
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
                Button {
                    showingAccountsActions = true
                } label: {
                    Image(systemName: "ellipsis").appEllipsisIcon()
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            NavigationStack {
                AccountEditorSheet(
                    title: "New Account",
                    currencyCode: settings.currencyCode,
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
        .sheet(isPresented: $showingAccountsActions) {
            NavigationStack {
                AccountsActionsSheet(
                    canUndo: undoRedoManager.canUndo,
                    canRedo: undoRedoManager.canRedo,
                    onUndo: {
                        do {
                            try undoRedoManager.undo()
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.undo")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t undo that action. Please try again."
                            )
                        }
                    },
                    onRedo: {
                        do {
                            try undoRedoManager.redo()
                        } catch {
                            SecurityLogger.shared.logSecurityError(error, context: "AccountsView.redo")
                            AppErrorCenter.shared.show(
                                title: "Error",
                                message: "Couldn’t redo that action. Please try again."
                            )
                        }
                    },
                    onAddAccount: { showingAddAccount = true }
                )
                .navigationTitle("Account Actions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingAccountsActions = false }
                    }
                }
            }
        }
        .sheet(item: $editingAccount) { account in
            NavigationStack {
                AccountEditorSheet(
                    title: "Edit Account",
                    currencyCode: settings.currencyCode,
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

private struct AccountsActionsSheet: View {
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        List {
            Section("Accounts") {
                Button {
                    onAddAccount()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }

            Section("History") {
                Button {
                    onUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)

                Button {
                    onRedo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
            }
        }
        .listStyle(.insetGrouped)
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
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    Text("Overview")
                        .appSectionTitleText()
                    Text("\(count) account\(count == 1 ? "" : "s")")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(netWorth, format: .currency(code: currencyCode))
                    .appTitleText()
                    .foregroundStyle(netWorth >= 0 ? .primary : AppDesign.Colors.danger(for: appColorMode))
            }

            HStack(spacing: AppDesign.Theme.Spacing.tight) {
                SummaryPill(title: "Assets", value: totalAssets, currencyCode: currencyCode, tint: AppDesign.Colors.success(for: appColorMode))
                SummaryPill(title: "Debt", value: totalDebt, currencyCode: currencyCode, tint: AppDesign.Colors.warning(for: appColorMode))
            }
        }
        .appCardSurface(stroke: .clear)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .appSecondaryBodyStrongText()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppDesign.Theme.Spacing.tight)
        .padding(.vertical, AppDesign.Theme.Spacing.small)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(AppDesign.Theme.Radius.compact)
    }
}

private struct AccountRow: View {
    let account: Account
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
            ZStack {
                Circle()
                    .fill(account.type.color.opacity(0.18))
                Image(systemName: account.type.icon)
                    .foregroundStyle(account.type.color)
                    .appDisplayText(AppDesign.Theme.DisplaySize.small, weight: .semibold)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                Text(account.name)
                    .appBodyStrongText()
                    .foregroundStyle(.primary)

                HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text(account.type.rawValue)
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    if account.isTrackingOnly {
                        Text("External")
                            .appCaption2StrongText()
                            .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
                            .padding(.vertical, AppDesign.Theme.Spacing.hairline)
                            .background(Capsule().fill(AppDesign.Colors.warning(for: appColorMode).opacity(0.12)))
                            .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
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
                .appSecondaryBodyStrongText()
                .foregroundStyle(account.balance >= 0 ? .primary : AppDesign.Colors.danger(for: appColorMode))
        }
        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
    }
}

private struct AccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appSettings) private var settings

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

	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
	                    Text("Current Balance")
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
	                    HStack(spacing: AppDesign.Theme.Spacing.compact) {
	                        Text(currencySymbol(for: settings.currencyCode))
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
