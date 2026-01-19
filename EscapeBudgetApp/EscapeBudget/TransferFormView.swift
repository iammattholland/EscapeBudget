import SwiftUI
import SwiftData

struct TransferFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    let transferID: UUID?
    private let sourceTransactionID: PersistentIdentifier?

    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var memo: String = ""
    @State private var status: TransactionStatus = .uncleared
    @State private var loadError: String?
    @State private var otherTransaction: Transaction?
    @State private var selectedOtherTransaction: Transaction?
    @FocusState private var isAmountFocused: Bool

    init(transferID: UUID? = nil, sourceTransactionID: PersistentIdentifier? = nil) {
        self.transferID = transferID
        self.sourceTransactionID = sourceTransactionID
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loadError {
                    Section {
                        Text(loadError)
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                    }
                }

                Section("Accounts") {
                    Picker("From", selection: $fromAccount) {
                        Text("Select").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }

                    Picker("To", selection: $toAccount) {
                        Text("Select").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                }

                Section("Details") {
                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .onChange(of: amountText) { _, newValue in
                                amountText = formatAmountInput(newValue)
                            }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Status", selection: $status) {
                        ForEach(TransactionStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    TextField("Memo", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                // Show linked transaction when editing
                if transferID != nil, let other = otherTransaction {
                    Section("Linked Transaction") {
                        Button {
                            selectedOtherTransaction = other
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(other.account?.name ?? "Unknown Account")
                                        .appSectionTitleText()
                                        .foregroundStyle(.primary)
                                    Text(other.amount >= 0 ? "Receiving account" : "Sending account")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(other.amount, format: .currency(code: currencyCode))
                                    .foregroundColor(other.amount >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                                Image(systemName: "chevron.right")
                                    .appCaptionText()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(item: $selectedOtherTransaction) { transaction in
                TransactionFormView(transaction: transaction)
            }
            .navigationTitle(transferID == nil ? "Add Transfer" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isAmountFocused = false
#if canImport(UIKit)
                        KeyboardUtilities.dismiss()
#endif
                    }
                }
            }
            .suppressGlobalKeyboardDoneToolbar()
            .onAppear { loadIfNeeded() }
        }
    }

    private var canSave: Bool {
        guard let fromAccount, let toAccount else { return false }
        if fromAccount.persistentModelID == toAccount.persistentModelID { return false }
        return parseAmount() != nil
    }

    private func parseAmount() -> Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: normalized) else { return nil }
        return value > 0 ? value : nil
    }

    /// Formats amount input to limit to 2 decimal places
    private func formatAmountInput(_ input: String) -> String {
        // Allow only digits and decimal point
        var filtered = input.filter { "0123456789.".contains($0) }

        // Handle multiple decimal points - keep only first
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            filtered = String(parts[0]) + "." + String(parts[1])
        }

        // Limit decimal places to 2
        if let dotIndex = filtered.firstIndex(of: ".") {
            let afterDot = filtered[filtered.index(after: dotIndex)...]
            if afterDot.count > 2 {
                let endIndex = filtered.index(dotIndex, offsetBy: 3)
                filtered = String(filtered[..<endIndex])
            }
        }

        return filtered
    }

    private func loadIfNeeded() {
        guard let transferID else { return }
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        do {
            let legs = try modelContext.fetch(descriptor)
            guard legs.count >= 2 else {
                loadError = "Could not load transfer."
                return
            }
            let outflow = legs.min(by: { $0.amount < $1.amount }) ?? legs[0]
            let inflow = legs.max(by: { $0.amount < $1.amount }) ?? legs[0]
            let sourceLeg = sourceTransactionID.flatMap { sourceID in
                legs.first(where: { $0.persistentModelID == sourceID })
            }

            fromAccount = outflow.account
            toAccount = inflow.account
            let inferredAmount = max(abs(outflow.amount), inflow.amount)

            // Format with 2 decimal places
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            amountText = formatter.string(from: NSDecimalNumber(decimal: inferredAmount)) ?? inferredAmount.formatted()

            let baseline = sourceLeg ?? outflow
            date = baseline.date
            memo = baseline.memo ?? ""
            status = baseline.status

            // Store reference to the other leg (not the one the user tapped)
            if let sourceLeg {
                otherTransaction = legs.first(where: { $0.persistentModelID != sourceLeg.persistentModelID })
            } else {
                otherTransaction = inflow
            }
        } catch {
            loadError = "Could not load transfer."
        }
    }

    private func save() {
        loadError = nil
        guard let fromAccount, let toAccount else { return }
        guard fromAccount.persistentModelID != toAccount.persistentModelID else { return }
        guard let amount = parseAmount() else { return }

        if let transferID {
            updateExistingTransfer(transferID: transferID, from: fromAccount, to: toAccount, amount: amount)
        } else {
            createNewTransfer(from: fromAccount, to: toAccount, amount: amount)
        }
    }

    private func createNewTransfer(from: Account, to: Account, amount: Decimal) {
        let id = UUID()
        let outflow = Transaction(
            date: date,
            payee: "Transfer",
            amount: -amount,
            memo: memo.isEmpty ? nil : memo,
            status: status,
            kind: .transfer,
            transferID: id,
            account: from,
            category: nil
        )
        let inflow = Transaction(
            date: date,
            payee: "Transfer",
            amount: amount,
            memo: memo.isEmpty ? nil : memo,
            status: status,
            kind: .transfer,
            transferID: id,
            account: to,
            category: nil
        )

        modelContext.insert(outflow)
        modelContext.insert(inflow)

        from.balance += -amount
        to.balance += amount

        let didSave = modelContext.safeSave(context: "TransferFormView.createNewTransfer")
        guard didSave else {
            loadError = "Couldn’t save transfer."
            return
        }
        dismiss()
    }

    private func updateExistingTransfer(transferID: UUID, from: Account, to: Account, amount: Decimal) {
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        do {
            var legs = try modelContext.fetch(descriptor)
            guard legs.count >= 2 else {
                loadError = "Could not update transfer."
                return
            }

            if legs.count > 2 {
                for extra in legs.dropFirst(2) {
                    if let account = extra.account {
                        account.balance -= extra.amount
                    }
                    modelContext.delete(extra)
                }
                legs = Array(legs.prefix(2))
            }

            let outflow = legs.min(by: { $0.amount < $1.amount }) ?? legs[0]
            let inflow = legs.max(by: { $0.amount < $1.amount }) ?? legs[0]

            if let account = outflow.account { account.balance -= outflow.amount }
            if let account = inflow.account { account.balance -= inflow.amount }

            outflow.date = date
            inflow.date = date
            outflow.memo = memo.isEmpty ? nil : memo
            inflow.memo = memo.isEmpty ? nil : memo
            outflow.status = status
            inflow.status = status
            outflow.kind = .transfer
            inflow.kind = .transfer
            outflow.transferID = transferID
            inflow.transferID = transferID
            outflow.category = nil
            inflow.category = nil

            outflow.account = from
            inflow.account = to
            outflow.amount = -amount
            inflow.amount = amount

            from.balance += -amount
            to.balance += amount

            try modelContext.save()
            dismiss()
        } catch {
            loadError = "Could not update transfer."
        }
    }
}

#Preview {
    TransferFormView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
