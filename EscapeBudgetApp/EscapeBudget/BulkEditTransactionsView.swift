import SwiftUI
import SwiftData

struct BulkEditTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    let transactionIDs: [PersistentIdentifier]

    @State private var changePayee = false
    @State private var payee: String = ""

    @State private var changeMemo = false
    @State private var memo: String = ""

    @State private var changeDate = false
    @State private var date: Date = Date()

    @State private var changeStatus = false
    @State private var status: TransactionStatus = .uncleared

    @State private var changeAccount = false
    @State private var account: Account?

    @State private var changeCategory = false
    @State private var category: Category?
    @State private var setUncategorized = false

    @State private var changeAmount = false
    @State private var amountText: String = ""
    @State private var amountIsIncome = false

    @State private var convertToTransfer = false

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                    }
                }

                Section {
                    Text("\(selectedTransactions.count) transaction(s) selected")
                        .foregroundStyle(.secondary)
                }

                Section("Payee") {
                    Toggle("Change Payee", isOn: $changePayee)
                    if changePayee {
                        TextField("Payee", text: $payee)
                    }
                }

                Section("Memo") {
                    Toggle("Change Memo", isOn: $changeMemo)
                    if changeMemo {
                        TextField("Memo", text: $memo, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .onChange(of: memo) { _, newValue in
                                let limit = TransactionTextLimits.maxMemoLength
                                guard newValue.count > limit else { return }
                                memo = String(newValue.prefix(limit))
                            }

                        HStack {
                            Spacer()
                            let limit = TransactionTextLimits.maxMemoLength
                            Text("\(min(memo.count, limit))/\(limit)")
                                .font(.caption2)
                                .foregroundStyle(memo.count >= limit ? AppColors.warning(for: appColorMode) : .secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Date") {
                    Toggle("Change Date", isOn: $changeDate)
                    if changeDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }

                Section("Status") {
                    Toggle("Change Status", isOn: $changeStatus)
                    if changeStatus {
                        Picker("Status", selection: $status) {
                            ForEach(TransactionStatus.allCases, id: \.self) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                    }
                }

                Section("Account") {
                    Toggle("Change Account", isOn: $changeAccount)
                        .disabled(!supportsAccountChange)
                    if changeAccount {
                        Picker("Account", selection: $account) {
                            Text("Select").tag(Optional<Account>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                    } else if !supportsAccountChange {
                        Text("Account changes aren’t available when transfers are selected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Category") {
                    Toggle("Change Category", isOn: $changeCategory)
                        .disabled(!supportsCategoryChange)
                    if changeCategory {
                        Toggle("Set Uncategorized", isOn: $setUncategorized)
                        if !setUncategorized {
                            Picker("Category", selection: $category) {
                                Text("Select").tag(Optional<Category>.none)
                                ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                    ForEach(group.sortedCategories) { category in
                                        Text(category.name).tag(Optional(category))
                                    }
                                }
                            }
                        }
                    } else if !supportsCategoryChange {
                        Text("Category changes only apply to standard (non-transfer) transactions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Amount") {
                    Toggle("Change Amount", isOn: $changeAmount)
                        .disabled(!supportsAmountChange)
                    if changeAmount {
                        Picker("Type", selection: $amountIsIncome) {
                            Text("Expense").tag(false)
                            Text("Income").tag(true)
                        }
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    } else if !supportsAmountChange {
                        Text("Amount changes aren't available when transfers are selected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Convert to Transfer") {
                    Toggle("Mark as Transfers", isOn: $convertToTransfer)
                        .disabled(!supportsConvertToTransfer)
                    if convertToTransfer {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                Text("This will convert \(standardTransactionCount) transaction(s) to unmatched transfers and remove their categories.")
                                    .font(.caption)
                            } icon: {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            Text("You can match them later in the Transfers Inbox or All Transactions view.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !supportsConvertToTransfer {
                        Text("No standard transactions selected to convert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Bulk Edit")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyChanges() }
                        .disabled(!hasAnyChanges)
                }
            }
        }
    }

    private var selectedTransactions: [Transaction] {
        transactionIDs.compactMap { modelContext.model(for: $0) as? Transaction }
    }

    private var hasAnyChanges: Bool {
        changePayee || changeMemo || changeDate || changeStatus || changeAccount || changeCategory || changeAmount || convertToTransfer
    }

    private var supportsAccountChange: Bool {
        !selectedTransactions.contains(where: { $0.isTransfer })
    }

    private var supportsAmountChange: Bool {
        !selectedTransactions.contains(where: { $0.isTransfer })
    }

    private var supportsCategoryChange: Bool {
        selectedTransactions.contains(where: { $0.kind == .standard })
    }

    private var supportsConvertToTransfer: Bool {
        standardTransactionCount > 0
    }

    private var standardTransactionCount: Int {
        selectedTransactions.filter { $0.kind == .standard }.count
    }

    private func parseAmount() -> Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: normalized) else { return nil }
        return value > 0 ? value : nil
    }

    @MainActor
    private func applyChanges() {
        errorMessage = nil

        if changeAmount && parseAmount() == nil {
            errorMessage = "Enter a valid amount."
            return
        }

        let newAmountAbsolute = parseAmount()

        for transaction in selectedTransactions {
            let old = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)
        }

        for transaction in selectedTransactions {
            // Convert to transfer first if requested (this affects subsequent operations)
            if convertToTransfer && transaction.kind == .standard {
                transaction.kind = .transfer
                transaction.category = nil
                transaction.transferID = nil
                transaction.transferInboxDismissed = false

                // Log the conversion
                TransactionHistoryService.append(
                    detail: "Bulk converted from Standard to Transfer.",
                    to: transaction,
                    in: modelContext
                )
            }

            if changePayee, transaction.kind == .standard {
                transaction.payee = payee
            }
            if changeMemo {
                transaction.memo = TransactionTextLimits.normalizedMemo(memo)
            }
            if changeDate {
                transaction.date = date
            }
            if changeStatus {
                transaction.status = status
            }

            if transaction.isTransfer {
                continue
            }

            if changeCategory, transaction.kind == .standard {
                transaction.category = setUncategorized ? nil : category
            }

            if changeAccount || changeAmount {
                let oldAccount = transaction.account
                let oldAmount = transaction.amount
                let newAccount = changeAccount ? account : oldAccount
                let newAmount: Decimal = {
                    guard changeAmount, let absolute = newAmountAbsolute else { return oldAmount }
                    return amountIsIncome ? absolute : -absolute
                }()

                if oldAccount?.persistentModelID == newAccount?.persistentModelID {
                    if let account = newAccount {
                        account.balance += (newAmount - oldAmount)
                    }
                } else {
                    if let old = oldAccount {
                        old.balance -= oldAmount
                    }
                    if let new = newAccount {
                        new.balance += newAmount
                    }
                }

                transaction.account = newAccount
                transaction.amount = newAmount
            }
        }

        do {
            try modelContext.save()
            for transaction in selectedTransactions {
                TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
            }
            DataChangeTracker.bump()
            dismiss()
        } catch {
            errorMessage = "Failed to apply changes."
        }
    }
}
