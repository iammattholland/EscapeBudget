import SwiftUI
import SwiftData

struct ReconcileAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    @Query(sort: \Account.name) private var accounts: [Account]
    
    @State private var selectedAccount: Account?
    @State private var actualBalanceInput: String = ""
    @State private var showingConfirm = false
    @State private var errorMessage: String?
    @FocusState private var isActualBalanceFocused: Bool

    init(preselectedAccount: Account? = nil) {
        _selectedAccount = State(initialValue: preselectedAccount)
    }

    private var parsedActualBalance: Decimal? {
        ImportParser.parseAmount(actualBalanceInput)
    }

    private var currentBalance: Decimal {
        selectedAccount?.balance ?? 0
    }

    private var delta: Decimal? {
        guard let actual = parsedActualBalance else { return nil }
        return actual - currentBalance
    }

    var body: some View {
        NavigationStack {
            List {
                errorSection
                accountSection
                actualBalanceSection
                summarySection
                reconcileButtonSection
            }
            .listStyle(.insetGrouped)
            .appListCompactSpacing()
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    isActualBalanceFocused = false
#if canImport(UIKit)
                    KeyboardUtilities.dismiss()
#endif
                }
            )
            .navigationTitle("Reconcile")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Confirm Reconciliation",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Create Adjustment", role: .none) {
                    reconcile()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(confirmMessage)
            }
            .onAppear {
                if selectedAccount == nil {
                    selectedAccount = accounts.first
                }
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Picker("Account", selection: $selectedAccount) {
                Text("Select").tag(nil as Account?)
                ForEach(accounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }
        }
    }

    private var actualBalanceSection: some View {
        Section("Actual Balance") {
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                Text("Enter the current balance shown by your bank. Escape Budget will create an adjustment transaction to match it.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text(currencySymbol(for: settings.currencyCode))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $actualBalanceInput)
                        .keyboardType(.decimalPad)
                        .focused($isActualBalanceFocused)
                }
            }
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            summaryRow(title: "In-app balance", value: currentBalance, tint: .primary)
            summaryRow(title: "Entered actual", value: parsedActualBalance ?? 0, tint: parsedActualBalance == nil ? .secondary : .primary)

            let value = delta ?? 0
            let tint: Color = value == 0 ? .secondary : (value >= 0 ? AppDesign.Colors.success(for: appColorMode) : AppDesign.Colors.danger(for: appColorMode))
            summaryRow(title: "Adjustment", value: value, tint: tint)
        }
    }

    private func summaryRow(title: String, value: Decimal, tint: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .currency(code: settings.currencyCode))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.currencySymbol ?? code
    }

    private var reconcileButtonSection: some View {
        Section {
            Button {
                showingConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Reconcile")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(reconcileDisabled)
        }
    }

    private var confirmMessage: String {
        guard let account = selectedAccount, let delta else {
            return "Create an adjustment transaction to match your entered balance?"
        }
        let formattedDelta = delta.formatted(.currency(code: settings.currencyCode))
        return "Create a \(formattedDelta) adjustment for \(account.name)?"
    }

    private var reconcileDisabled: Bool {
        guard selectedAccount != nil else { return true }
        guard let delta else { return true }
        return delta == 0
    }

    @MainActor
    private func reconcile() {
        errorMessage = nil
        guard let account = selectedAccount else { return }
        guard let delta else { return }
        guard delta != 0 else { return }

        let transaction = Transaction(
            date: Date(),
            payee: "Reconciliation",
            amount: delta,
            memo: "Balance adjustment",
            status: .reconciled,
            kind: .adjustment,
            transferID: nil,
            account: account,
            category: nil,
            parentTransaction: nil,
            tags: nil,
            isDemoData: false
        )
        modelContext.insert(transaction)
        account.balance += delta
        account.lastReconciledAt = Date()
        account.reconcileReminderLastThresholdSent = 0

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn’t reconcile this account. Please try again."
        }
    }
}
