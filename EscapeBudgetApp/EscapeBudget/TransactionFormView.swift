import SwiftUI
import SwiftData

struct TransactionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoRedoManager) private var undoRedoManager
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \CategoryGroup.name) private var categoryGroups: [CategoryGroup]
    
    @State private var amount: Decimal = 0.0
    @State private var amountInput: String = ""
    @State private var amountType: AmountType = .expense
    @State private var payee: String = ""
    @State private var date: Date = Date()
    @State private var memo: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var transactionKind: TransactionKind = .standard
    @State private var showingNewAccountSheet = false
    @State private var showingNewCategorySheet = false
    @State private var newAccountName = ""
    @State private var newAccountType: AccountType = .chequing
    @State private var newAccountBalanceInput = ""
    @State private var newCategoryName = ""
    @State private var newCategoryGroup: CategoryGroup?
    private enum CategoryCreationStep {
        case groupSelection, details
    }
    @State private var categoryCreationStep: CategoryCreationStep = .groupSelection
    @State private var showingNewGroupSheet = false
    @State private var newGroupName = ""
    @State private var newGroupType: CategoryGroupType = .expense
    @State private var isSplit: Bool = false
    @State private var subtransactions: [SubTransactionData] = []
    @State private var purchasedItems: [PurchasedItemDraft] = []
    @State private var editingPurchasedItemID: UUID? = nil
    @State private var selectedTags: [TransactionTag] = []
    @State private var showingReceiptScanner = false
    @State private var scannedImage: UIImage?
    @State private var parsedReceipt: ReceiptOCRService.ParsedReceipt?
    @State private var showingReceiptReview = false
    @State private var receiptImage: ReceiptImage?
    @State private var showingTagPicker = false
    @FocusState private var focusedField: FocusField?
    @State private var showingRemoveSplitConfirmation = false
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var showingDeleteConfirmation = false
	@Query(sort: \Transaction.date, order: .reverse) private var existingTransactions: [Transaction]
	@State private var payeeSuggestions: [String] = []
	@State private var transferBaseTransaction: Transaction?
    @State private var processingReview: ProcessingReviewSheetItem?
    private let memoLimit = TransactionTextLimits.maxMemoLength

    private var sortedHistoryEntries: [TransactionHistoryEntry] {
        guard let transaction = transactionToEdit else { return [] }
        return (transaction.historyEntries ?? []).sorted { $0.timestamp > $1.timestamp }
    }
    
    private var splitTotal: Decimal {
        subtransactions.reduce(.zero) { $0 + $1.amount }
    }
    
    private var splitRemaining: Decimal {
        amount - splitTotal
    }
    
    private var canSave: Bool {
        if isSplit {
            return !subtransactions.isEmpty && splitTotal == amount && subtransactions.count >= 2
        }
        return true
    }
    
    private var numericFieldFocused: Bool {
        guard let focusedField else { return false }
        switch focusedField {
        case .amount:
            return true
        case .splitAmount(_):
            return true
        }
    }
    
    private func normalizedSplitAmount(_ value: Decimal) -> Decimal {
        guard amount != 0 else { return value }
        if amount < 0 {
            return value == 0 ? 0 : -abs(value)
        } else {
            return abs(value)
        }
    }
    
    private func enforceSplitSigns() {
        guard amount != 0 else { return }
        for index in subtransactions.indices {
            subtransactions[index].amount = normalizedSplitAmount(subtransactions[index].amount)
        }
    }
    
    private func formatCurrency(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private var purchasedItemsTotal: Decimal {
        purchasedItems.reduce(.zero) { $0 + $1.price }
    }

    private var purchasedItemsAmountDiff: Decimal {
        decimalAbs(decimalAbs(amount) - decimalAbs(purchasedItemsTotal))
    }

    private var purchasedItemsShouldWarnMismatch: Bool {
        guard !purchasedItems.isEmpty else { return false }
        guard amount != 0 else { return false }
        return purchasedItemsAmountDiff > Decimal(string: "0.01")!
    }

    private var canAddPurchasedItem: Bool {
        purchasedItems.count < TransactionTextLimits.maxPurchasedItemsPerTransaction
    }

    @ViewBuilder
    private var purchasedItemsSection: some View {
        Section {
            Button {
                addPurchasedItem()
            } label: {
                Label("Add Purchase Item", systemImage: "plus.circle")
            }
            .disabled(!canAddPurchasedItem)

            if purchasedItems.isEmpty {
                Text("Add items from this purchase for quick reference and future insights.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(purchasedItems) { item in
                    Button {
                        editingPurchasedItemID = item.id
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name.isEmpty ? "Item" : item.name)
                                    .foregroundStyle(.primary)
                                if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(item.note)
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(item.price, format: .currency(code: currencyCode))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deletePurchasedItems)
            }
        } header: {
            Text("Purchased Items")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Items: \(purchasedItems.count) • Total: \(formatCurrency(purchasedItemsTotal))")
                if purchasedItemsShouldWarnMismatch {
                    Text("Total doesn’t match transaction amount (\(formatCurrency(decimalAbs(amount)))). Difference: \(formatCurrency(purchasedItemsAmountDiff)).")
                        .foregroundStyle(AppColors.warning(for: appColorMode))
                }
                if !canAddPurchasedItem {
                    Text("Limit reached (\(TransactionTextLimits.maxPurchasedItemsPerTransaction) items per transaction).")
                }
            }
            .appCaptionText()
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var receiptSection: some View {
        Section {
            if let receipt = receiptImage {
                // Receipt preview
                HStack(spacing: 12) {
                    if let imageData = receipt.imageData,
	                       let uiImage = UIImage(data: imageData) {
	                        Image(uiImage: uiImage)
	                            .resizable()
	                            .scaledToFill()
	                            .frame(width: 60, height: 60)
	                            .cornerRadius(AppTheme.Radius.xSmall)
	                            .clipped()
	                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.merchant ?? "Receipt")
                            .appSectionTitleText()
                        if let date = receipt.receiptDate {
                            Text(date, style: .date)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        if let total = receipt.totalAmount {
                            Text(total.formatted(.currency(code: currencyCode)))
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        receiptImage = nil
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                    }
                }

                if !receipt.items.isEmpty {
                    Text("\(receipt.items.count) item\(receipt.items.count == 1 ? "" : "s") extracted")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showingReceiptScanner = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                }
            }
        } header: {
            Text("Receipt")
        } footer: {
            if receiptImage == nil {
                Text("Attach a receipt image to extract items and details automatically.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func logHistory(for transaction: Transaction, detail: String) {
        TransactionHistoryService.append(detail: detail, to: transaction, in: modelContext)
    }
    
    private func recordChanges(for transaction: Transaction,
                               oldAmount: Decimal,
                               oldAccount: Account?,
                               oldCategory: Category?,
                               oldPayee: String,
                               oldDate: Date,
                               oldMemo: String?,
                               wasSplit: Bool) {
        var entries: [String] = []
        
        if oldAmount != amount {
            entries.append("Amount changed from \(formatCurrency(oldAmount)) to \(formatCurrency(amount)).")
        }
        
        if let oldAccount, let newAccount = transaction.account, oldAccount !== newAccount {
            entries.append("Account changed from \(oldAccount.name) to \(newAccount.name).")
        }
        
        let newCategory = transaction.category
        if oldCategory !== newCategory {
            if let newCategory {
                let previous = oldCategory?.name ?? "Uncategorized"
                entries.append("Category changed from \(previous) to \(newCategory.name).")
            }
        }
        
        if oldPayee != payee {
            entries.append("Payee changed from \"\(oldPayee)\" to \"\(payee)\".")
        }
        
        if oldDate != date {
            entries.append("Date changed from \(formatDate(oldDate)) to \(formatDate(date)).")
        }
        
        if (oldMemo ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != memo.trimmingCharacters(in: .whitespacesAndNewlines) {
            entries.append("Memo updated.")
        }
        
        let isCurrentlySplit = !(transaction.subtransactions ?? []).isEmpty
        if wasSplit != isCurrentlySplit {
            if isCurrentlySplit {
                let count = transaction.subtransactions?.count ?? 0
                entries.append("Transaction split into \(count) part\(count == 1 ? "" : "s").")
            } else {
                entries.append("Split removed.")
            }
        }
        
        for entry in entries {
            logHistory(for: transaction, detail: entry)
        }
    }

    private struct PurchasedItemSnapshot {
        let id: PersistentIdentifier
        let name: String
        let price: Decimal
        let note: String?
        let order: Int
    }

    private func recordPurchasedItemChanges(
        for transaction: Transaction,
        oldItems: [PurchasedItemSnapshot],
        newDrafts: ArraySlice<PurchasedItemDraft>
    ) {
        let maxDetails = 12

        var oldByID: [PersistentIdentifier: PurchasedItemSnapshot] = [:]
        oldByID.reserveCapacity(oldItems.count)
        for item in oldItems {
            oldByID[item.id] = item
        }

	        let newIDs = Set(newDrafts.compactMap(\.modelID))
	        let removed = oldItems.filter { !newIDs.contains($0.id) }

	        var addedCount = 0
	        var updatedCount = 0
	        let removedCount = removed.count

        var messages: [String] = []
        messages.reserveCapacity(maxDetails)

        for old in removed.prefix(maxDetails) {
            messages.append("Removed purchase item: \(old.name).")
        }

        for draft in newDrafts {
            let normalizedName = TransactionTextLimits.normalizedPurchasedItemName(draft.name)
            let normalizedNote = TransactionTextLimits.normalizedPurchasedItemNote(draft.note)

            if let modelID = draft.modelID, let old = oldByID[modelID] {
                let oldNote = TransactionTextLimits.normalizedPurchasedItemNote(old.note)
                let nameChanged = old.name != normalizedName
                let priceChanged = old.price != draft.price
                let noteChanged = (oldNote ?? "") != (normalizedNote ?? "")

                if nameChanged || priceChanged || noteChanged {
                    updatedCount += 1
                    if messages.count < maxDetails {
                        if nameChanged && priceChanged {
                            messages.append("Updated purchase item: renamed to \(normalizedName) and price changed.")
                        } else if nameChanged {
                            messages.append("Updated purchase item: renamed to \(normalizedName).")
                        } else if priceChanged {
                            messages.append("Updated purchase item: \(normalizedName) price changed.")
                        } else {
                            messages.append("Updated purchase item: \(normalizedName) note changed.")
                        }
                    }
                }
            } else {
                addedCount += 1
                if messages.count < maxDetails {
                    messages.append("Added purchase item: \(normalizedName).")
                }
            }
        }

        let totalChanges = addedCount + updatedCount + removedCount
        guard totalChanges > 0 else { return }

        for message in messages {
            logHistory(for: transaction, detail: message)
        }

        if totalChanges > messages.count {
            logHistory(for: transaction, detail: "Updated purchase items (\(totalChanges) changes).")
        }
    }
    
    private static let splitAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    private static func plainAmountInput(for value: Decimal) -> String {
        guard value != 0 else { return "" }
        let absolute = NSDecimalNumber(decimal: abs(value))
        return TransactionFormView.splitAmountFormatter.string(from: absolute) ?? ""
    }
    
    private func formattedSplitAmount(_ value: Decimal) -> String {
        let absolute = NSDecimalNumber(decimal: abs(value))
        return TransactionFormView.splitAmountFormatter.string(from: absolute) ?? ""
    }
    
    private func decimalFromInput(_ input: String) -> Decimal {
        let sanitized = input
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Decimal(string: sanitized) ?? 0
    }

    private func decimalAbs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
    
    private func isSplitFieldFocused(_ id: UUID) -> Bool {
        if case .splitAmount(let focusedId)? = focusedField {
            return focusedId == id
        }
        return false
    }
    
    private func splitAmountTextBinding(for sub: Binding<SubTransactionData>) -> Binding<String> {
        Binding(
            get: {
                let currentAmount = sub.wrappedValue.amount
                if currentAmount == 0, isSplitFieldFocused(sub.wrappedValue.id) {
                    return ""
                }
                return formattedSplitAmount(currentAmount)
            },
            set: { newValue in
                let decimalValue = decimalFromInput(newValue)
                sub.wrappedValue.amount = normalizedSplitAmount(decimalValue)
            }
        )
    }
    
    private var amountTextBinding: Binding<String> {
        Binding(
            get: {
                amountInput
            },
            set: { newValue in
                amountInput = newValue
                let absoluteValue = decimalFromInput(newValue)
                amount = amountType == .income ? absoluteValue : -absoluteValue
                enforceSplitSigns()
            }
        )
    }
    
    private var amountIndicator: (text: String, color: Color)? {
        guard !amountInput.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // Show Transfer badge if transaction is a transfer
        if transactionKind == .transfer {
            return ("Transfer", AppColors.tint(for: appColorMode))
        }

        return amountType == .income
            ? ("Income", AppColors.success(for: appColorMode))
            : ("Expense", AppColors.danger(for: appColorMode))
    }
    
    private var amountColor: Color {
        if amountInput.trimmingCharacters(in: .whitespaces).isEmpty {
            return .primary
        }
        return amountType == .income ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode)
    }
    
    private var currencySymbol: String {
        TransactionFormView.currencySymbol(for: currencyCode)
    }
    
    private static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.currencySymbol ?? code
    }
    
    private var isAmountIncome: Bool { amountType == .income }

    private var categorySelectionLabel: String {
        if transactionKind == .transfer {
            return "Transfer"
        }
        if transactionKind == .ignored {
            return "Ignored"
        }
        return selectedCategory?.name ?? "Uncategorized"
    }
    
    private var distinctPayees: [String] {
        Array(Set(existingTransactions.map { $0.payee }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private var categorySuggestions: [Category] {
        let trimmed = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var counts: [PersistentIdentifier: (category: Category, count: Int)] = [:]
        let matches = existingTransactions.filter { $0.payee.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        for transaction in matches {
            guard let category = transaction.category else { continue }
            guard category.name.localizedCaseInsensitiveCompare("Uncategorized") != .orderedSame else { continue }
            let id = category.persistentModelID
            var entry = counts[id] ?? (category, 0)
            entry.count += 1
            counts[id] = entry
        }
        return counts.values
            .sorted { $0.count > $1.count }
            .map { $0.category }
            .prefix(4)
            .map { $0 }
    }
    
    private func updatePayeeSuggestions() {
        let trimmed = payee.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            payeeSuggestions = []
            return
        }
        payeeSuggestions = distinctPayees
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            .prefix(5)
            .map { $0 }
    }
    
    private func requiredFieldIssues() -> [String] {
        var issues: [String] = []
        if payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Payee")
        }
        if amount == 0 {
            issues.append("Amount")
        }
        if selectedAccount == nil {
            issues.append("Account")
        }
        // Date is always set, but ensure future proofing
        return issues
    }
    
    private func validationMessageIfNeeded() -> String? {
        let issues = requiredFieldIssues()
        guard !issues.isEmpty else { return nil }
        if issues.count == 1 {
            return "\(issues[0]) is required."
        }
        let last = issues.last!
        let prefix = issues.dropLast().joined(separator: ", ")
        return "\(prefix), and \(last) are required."
    }
    
    private func applyAmountSign(isIncome: Bool) {
        amountType = isIncome ? .income : .expense
        let absoluteValue = decimalFromInput(amountInput)
        amount = isIncome ? absoluteValue : -absoluteValue
        enforceSplitSigns()
    }
    
    var transactionToEdit: Transaction?
    
    private enum FocusField: Hashable {
        case amount
        case splitAmount(UUID)
    }
    
    private enum AmountType {
        case income
        case expense
    }
    
    // Helper struct for split UI
    struct SubTransactionData: Identifiable {
        let id = UUID()
        var amount: Decimal = 0.0
        var category: Category?
        var memo: String = ""
    }

    struct PurchasedItemDraft: Identifiable {
        let id: UUID
        var modelID: PersistentIdentifier?
        var name: String
        var price: Decimal
        var priceInput: String
        var note: String

        init(
            id: UUID = UUID(),
            modelID: PersistentIdentifier? = nil,
            name: String = "",
            price: Decimal = 0,
            note: String = ""
        ) {
            self.id = id
            self.modelID = modelID
            self.name = name
            self.price = price
            self.priceInput = TransactionFormView.plainAmountInput(for: price)
            self.note = note
        }

        init(model: PurchasedItem) {
            self.id = UUID()
            self.modelID = model.persistentModelID
            self.name = model.name
            self.price = model.price
            self.priceInput = NSDecimalNumber(decimal: model.price).stringValue
            self.note = model.note ?? ""
        }
    }

    private struct ProcessingReviewSheetItem: Identifiable {
        let id = UUID()
        let transaction: Transaction
        let events: [TransactionProcessor.Event]
    }
    
    init(transaction: Transaction? = nil, defaultAccount: Account? = nil) {
        self.transactionToEdit = transaction
        let existingAmount = transaction?.amount ?? 0
        let initialAmountType: AmountType = {
            if let transaction, transaction.amount < 0 {
                return .expense
            } else if transaction?.amount == 0 {
                return .expense
            }
            return .income
        }()
        
        if let transaction = transaction {
            _amount = State(initialValue: transaction.amount)
            _payee = State(initialValue: transaction.payee)
            _date = State(initialValue: transaction.date)
            _memo = State(initialValue: transaction.memo ?? "")
            _selectedAccount = State(initialValue: transaction.account)
            _selectedCategory = State(initialValue: transaction.category)
            _selectedTags = State(initialValue: transaction.tags ?? [])
            _transactionKind = State(initialValue: transaction.kind)

            let items = (transaction.purchasedItems ?? [])
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            _purchasedItems = State(initialValue: items.map { PurchasedItemDraft(model: $0) })
            _receiptImage = State(initialValue: transaction.receipt)

            if let subs = transaction.subtransactions, !subs.isEmpty {
                _isSplit = State(initialValue: true)
                let normalize: (Decimal) -> Decimal = { value in
                    if transaction.amount == 0 {
                        return value
                    }
                    if transaction.amount < 0 {
                        return value == 0 ? 0 : -abs(value)
                    } else {
                        return abs(value)
                    }
                }
                _subtransactions = State(initialValue: subs.map { SubTransactionData(amount: normalize($0.amount), category: $0.category, memo: $0.memo ?? "") })
            }
        } else if let defaultAccount {
            _selectedAccount = State(initialValue: defaultAccount)
        }
        
        _amountInput = State(initialValue: TransactionFormView.plainAmountInput(for: existingAmount))
        _amountType = State(initialValue: transaction == nil ? .expense : initialAmountType)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payee")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Enter payee name", text: $payee)
                        if !payeeSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(payeeSuggestions, id: \.self) { suggestion in
                                    Button {
                                        payee = suggestion
                                        payeeSuggestions = []
                                    } label: {
                                        HStack {
                                            Text(suggestion)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
	                                    }
	                                }
	                            }
	                            .background(Color(.systemGray6))
	                            .cornerRadius(AppTheme.Radius.xSmall)
	                        }
	                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Amount")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(currencySymbol)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(amountColor)
                            TextField("", text: amountTextBinding, prompt: Text("0.00"))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amount)
                                .foregroundColor(amountColor)
                            
                            if let indicator = amountIndicator {
                                Text(indicator.text)
                                    .appCaptionText()
                                    .fontWeight(.semibold)
                                    .foregroundColor(indicator.color)
                                    .padding(.horizontal, AppTheme.Spacing.small)
                                    .padding(.vertical, 4)
                                    .background(indicator.color.opacity(0.15))
                                    .cornerRadius(AppTheme.Radius.button)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Date")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        DatePicker("Transaction Date", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memo")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Add notes...", text: $memo, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .onChange(of: memo) { _, newValue in
                                guard newValue.count > memoLimit else { return }
                                memo = String(newValue.prefix(memoLimit))
                            }

                        HStack {
                            Spacer()
                            Text("\(min(memo.count, memoLimit))/\(memoLimit)")
                                .font(.caption2)
                                .foregroundStyle(memo.count >= memoLimit ? AppColors.warning(for: appColorMode) : .secondary)
                                .monospacedDigit()
                        }
                    }
                }
                
                Section("Account & Category") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Menu {
                            Button("Select") { selectedAccount = nil }
                            Divider()
                            ForEach(accounts) { account in
                                Button(account.name) { selectedAccount = account }
                            }
                        } label: {
                            HStack {
                                Text(selectedAccount?.name ?? "Select")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Account")
                        
                        Button {
                            showingNewAccountSheet = true
                        } label: {
                            Label("Create New Account", systemImage: "plus.circle")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    
                    if !isSplit {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Menu {
                                Button("Uncategorized") {
                                    // If switching from transfer to uncategorized, unmatch
                                    if transactionKind == .transfer, let transaction = transactionToEdit {
                                        unmatchTransfer(transaction)
                                    }
                                    transactionKind = .standard
                                    selectedCategory = nil
                                }

                                Divider()

                                Button("Transfer") {
                                    if let transaction = transactionToEdit {
                                        // Convert to transfer but DON'T show picker
                                        if transaction.kind == .standard {
                                            transaction.kind = .transfer
                                            transaction.category = nil
                                            transaction.transferID = nil
                                            transaction.transferInboxDismissed = false

                                            // Update state variables to match
                                            transactionKind = .transfer
                                            selectedCategory = nil

                                            logHistory(for: transaction, detail: "Converted from Standard to Transfer.")
                                            _ = modelContext.safeSave(context: "TransactionFormView.Transfer button")
                                        } else {
                                            // Already a transfer, just update state
                                            transactionKind = .transfer
                                            selectedCategory = nil
                                        }
                                    } else {
                                        // For new transactions, just set the kind
                                        transactionKind = .transfer
                                        selectedCategory = nil
                                    }
                                }

                                Button("Ignore Transaction") {
                                    transactionKind = .ignored
                                    selectedCategory = nil
                                }

                                Divider()

                                ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                    Menu(group.name) {
                                        ForEach(group.sortedCategories) { category in
                                            Button(category.name) {
                                                // If switching from transfer to regular category, unmatch
                                                if transactionKind == .transfer, let transaction = transactionToEdit {
                                                    unmatchTransfer(transaction)
                                                }
                                                transactionKind = .standard
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(categorySelectionLabel)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Category")
	                            
	                        Button {
	                            if newCategoryGroup == nil {
	                                newCategoryGroup = selectedCategory?.group ?? categoryGroups.first
	                            }
                            categoryCreationStep = .groupSelection
                            showingNewCategorySheet = true
                        } label: {
                                Label("Create New Category", systemImage: "plus.circle")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            
	                        if !categorySuggestions.isEmpty {
	                            VStack(alignment: .leading, spacing: 6) {
	                                Text("Quick Categories")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(categorySuggestions) { suggestion in
                                                Button {
                                                    selectedCategory = suggestion
                                                } label: {
                                                    Text(suggestion.name)
                                                        .appCaptionText()
                                                        .fontWeight(.semibold)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(
                                                            Capsule()
                                                                .fill((selectedCategory?.persistentModelID == suggestion.persistentModelID) ? AppColors.tint(for: appColorMode).opacity(0.2) : Color(.systemGray6))
                                                        )
                                                        .overlay(
                                                            Capsule()
                                                                .stroke(selectedCategory?.persistentModelID == suggestion.persistentModelID ? AppColors.tint(for: appColorMode) : Color(.systemGray4), lineWidth: 1)
                                                        )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
	                            }
	                            .padding(.top, 4)
	                        }
		                    }
		                }
                }

                // Transfer Information Section - only shown when transactionKind is .transfer
                if transactionKind == .transfer {
                    if let transaction = transactionToEdit {
                        Section("Transfer Information") {
                            transferInformationContent(for: transaction)
                        }
                    } else {
                        // For new transactions being created as transfers
                        Section("Transfer Information") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Save this transaction first to match it with a transfer in another account.")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Tags") {
                    if selectedTags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedTags) { tag in
                                    TransactionTagChip(tag: tag)
                                        .onTapGesture {
                                            selectedTags.removeAll { $0.persistentModelID == tag.persistentModelID }
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button {
                        showingTagPicker = true
                    } label: {
                        Label(selectedTags.isEmpty ? "Add Tags" : "Edit Tags", systemImage: "tag")
                    }
                }
                
                Section("Split Transaction") {
                    Toggle(isOn: $isSplit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Split")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("Divide this amount across multiple categories.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: isSplit) { _, newValue in
                        if newValue {
                            if subtransactions.isEmpty {
                                subtransactions = [SubTransactionData(), SubTransactionData()]
                            }
                            selectedCategory = nil
                            enforceSplitSigns()
                        } else {
                            subtransactions.removeAll()
                            focusedField = nil
                        }
                    }
                    
                    if isSplit {
                        ForEach($subtransactions) { $sub in
                            let subID = sub.id
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Split Amount")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        Text(amount < 0 ? "-\(currencySymbol)" : currencySymbol)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                        TextField("", text: splitAmountTextBinding(for: $sub), prompt: Text("0.00"))
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .splitAmount(subID))
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Split Category")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Picker("Split Category", selection: $sub.category) {
                                        Text("Select").tag(nil as Category?)
                                        ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                            if let categories = group.categories {
                                                ForEach(categories) { category in
                                                    Text(category.name).tag(category as Category?)
                                                }
                                            }
                                        }
                                    }
                                    .labelsHidden()
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Split Memo")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    TextField("Optional note", text: $sub.memo)
                                        .appCaptionText()
                                        .onChange(of: sub.memo) { _, newValue in
                                            guard newValue.count > memoLimit else { return }
                                            sub.memo = String(newValue.prefix(memoLimit))
                                        }

                                    HStack {
                                        Spacer()
                                        Text("\(min(sub.memo.count, memoLimit))/\(memoLimit)")
                                            .font(.caption2)
                                            .foregroundStyle(sub.memo.count >= memoLimit ? AppColors.warning(for: appColorMode) : .secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { indexSet in
                            subtransactions.remove(atOffsets: indexSet)
                        }
                        
                        Button {
                            subtransactions.append(SubTransactionData())
                            enforceSplitSigns()
                        } label: {
                            Label("Add Split", systemImage: "plus.circle")
                        }
                        
                        VStack(spacing: 6) {
                            HStack {
                                Text("Split Total")
                                Spacer()
                                Text(splitTotal, format: .currency(code: currencyCode))
                                    .fontWeight(.semibold)
                                    .foregroundColor(splitTotal == amount ? .primary : AppColors.warning(for: appColorMode))
                            }
                            
                            HStack {
                                Text("Remaining")
                                Spacer()
                                Text(splitRemaining, format: .currency(code: currencyCode))
                                    .fontWeight(.semibold)
                                    .foregroundColor(splitRemaining == 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                            }
                            
                            Text("Split amounts must equal the transaction total before saving.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                
                if let parentTransaction = transactionToEdit?.parentTransaction {
                    Section("Split Options") {
                        Text("This transaction is part of a split (\(parentTransaction.payee)). Removing the split will restore the original transaction.")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        
                        Button(role: .destructive) {
                            showingRemoveSplitConfirmation = true
                        } label: {
                            Label("Remove Split", systemImage: "link.badge.minus")
                        }
                    }
                }
                purchasedItemsSection
                receiptSection

                if transactionToEdit != nil {
                    Section("History") {
                        if sortedHistoryEntries.isEmpty {
                            Text("No history yet")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
	                            ForEach(sortedHistoryEntries) { entry in
	                                VStack(alignment: .leading, spacing: 4) {
	                                    Text(entry.detail)
	                                        .appSecondaryBodyText()
	                                    Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
	                                        .appCaptionText()
	                                        .foregroundStyle(.secondary)
	                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                // Delete section - only show when editing
                if transactionToEdit != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Transaction", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .onChange(of: amount) { _, _ in
                guard isSplit else { return }
                enforceSplitSigns()
            }
            .onChange(of: payee) { _, _ in
                updatePayeeSuggestions()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(transactionToEdit == nil ? "New Transaction" : "Edit Transaction")
            .toolbar {
                if transactionToEdit == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let message = validationMessageIfNeeded() {
                            validationMessage = message
                            showingValidationAlert = true
                        } else {
                            saveTransaction()
                        }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if numericFieldFocused {
                        if focusedField == .amount {
                            let isIncomeSelected = isAmountIncome
                            HStack(spacing: 8) {
                                Button {
                                    applyAmountSign(isIncome: false)
                                } label: {
                                    Text("Expense")
                                        .appCaptionText()
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.danger(for: appColorMode))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.button)
                                                .fill((amount < 0 ? AppColors.danger(for: appColorMode).opacity(0.2) : AppColors.danger(for: appColorMode).opacity(0.08)))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.button)
                                                .stroke(AppColors.danger(for: appColorMode).opacity(amount < 0 ? 1 : 0.4), lineWidth: amount < 0 ? 2 : 1)
                                        )
                                }
                                
                                Button {
                                    applyAmountSign(isIncome: true)
                                } label: {
                                    Text("Income")
                                        .appCaptionText()
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.success(for: appColorMode))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.button)
                                                .fill((isIncomeSelected ? AppColors.success(for: appColorMode).opacity(0.2) : AppColors.success(for: appColorMode).opacity(0.08)))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.button)
                                                .stroke(AppColors.success(for: appColorMode).opacity(isIncomeSelected ? 1 : 0.4), lineWidth: isIncomeSelected ? 2 : 1)
                                        )
                                }
                            }
                        } else {
                            Button("±") {
                                toggleNegativeForFocusedField()
                            }
                        }
                    }
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                        dismissKeyboard()
                    }
                }
            }
            .alert("Remove split?", isPresented: $showingRemoveSplitConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove Split", role: .destructive) {
                    removeSplit()
                }
            } message: {
                Text("All split entries will be removed and the original transaction will reappear.")
            }
            .alert("Delete Transaction?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTransaction()
                }
            } message: {
                Text("This transaction will be permanently deleted. This action cannot be undone.")
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if newValue == .amount || oldValue == .amount {
                    amountInput = TransactionFormView.plainAmountInput(for: amount)
                }
            }
            .onChange(of: amount) { _, newValue in
                if focusedField != .amount {
                    amountInput = TransactionFormView.plainAmountInput(for: newValue)
                }
            }
            .suppressGlobalKeyboardDoneToolbar()
        }
        .alert("Missing Information", isPresented: $showingValidationAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(validationMessage)
        })
        .onAppear {
            updatePayeeSuggestions()
            if memo.count > memoLimit {
                memo = String(memo.prefix(memoLimit))
            }
        }
        .sheet(isPresented: $showingNewAccountSheet) {
            NavigationStack {
                Form {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account Name")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
	                        TextField("Chequing", text: $newAccountName)
	                            .padding(AppTheme.Spacing.tight)
	                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.compact).fill(Color(.secondarySystemFill)))
                        
                        Text("Account Type")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Picker("Account Type", selection: $newAccountType) {
                            ForEach(AccountType.allCases) { type in
                                Text(type.rawValue.capitalized).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        
	                    Text("Starting Balance")
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
	                    ZStack(alignment: .leading) {
	                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact)
	                            .fill(Color(.secondarySystemFill))
	                        HStack(spacing: 6) {
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0.00", text: $newAccountBalanceInput)
                                    .keyboardType(.decimalPad)
                            }
                            .padding(.horizontal, 12)
	                            .padding(.vertical, AppTheme.Spacing.small)
	                    }
                    }
                    .padding(.vertical, 8)
                }
                .navigationTitle("New Account")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewAccountForm()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            createNewAccountFromSheet()
                        }
                        .disabled(newAccountName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
        .sheet(isPresented: $showingNewCategorySheet) {
            NavigationStack {
                Form {
                    if categoryCreationStep == .groupSelection {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose a Group")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            
                            Picker("Group", selection: Binding(get: {
                                newCategoryGroup ?? categoryGroups.first
                            }, set: { newValue in
                                newCategoryGroup = newValue
                            })) {
                                ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                    Text(group.name).tag(Optional(group))
                                }
                            }
                            .pickerStyle(.inline)
                            
                            Button {
                                showingNewGroupSheet = true
                            } label: {
                                Label("Create New Group", systemImage: "plus.circle")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if let group = newCategoryGroup {
                                Text("Group: \(group.name)")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("Category Name")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
	                            TextField("Groceries", text: $newCategoryName)
	                                .padding(AppTheme.Spacing.tight)
	                                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.compact).fill(Color(.secondarySystemFill)))
                        }
                        .padding(.vertical, 8)
                    }
                }
                .navigationTitle(categoryCreationStep == .groupSelection ? "Select Group" : "New Category")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewCategoryForm()
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if categoryCreationStep == .details {
                            Button("Back") {
                                categoryCreationStep = .groupSelection
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if categoryCreationStep == .groupSelection {
                            Button("Next") {
                                categoryCreationStep = .details
                            }
                            .disabled((newCategoryGroup ?? categoryGroups.first) == nil)
                        } else {
                            Button("Add") {
                                createNewCategoryFromSheet()
                            }
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty || (newCategoryGroup ?? categoryGroups.first) == nil)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
        .sheet(isPresented: $showingNewGroupSheet) {
            NavigationStack {
                Form {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Group Name")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
	                        TextField("Living Expenses", text: $newGroupName)
	                            .padding(AppTheme.Spacing.tight)
	                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.compact).fill(Color(.secondarySystemFill)))
                        
                        Text("Group Type")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Picker("Group Type", selection: $newGroupType) {
                            ForEach(CategoryGroupType.allCases, id: \.self) { type in
                                Text(type.rawValue.capitalized).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 8)
                }
                .navigationTitle("New Group")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewGroupForm()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            createNewGroupFromSheet()
                        }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
        .sheet(isPresented: $showingTagPicker) {
            NavigationStack {
                TransactionTagsPickerView(selectedTags: $selectedTags)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingPurchasedItemID != nil },
            set: { if !$0 { editingPurchasedItemID = nil } }
        )) {
            NavigationStack {
                if let editingPurchasedItemID,
                   let index = purchasedItems.firstIndex(where: { $0.id == editingPurchasedItemID }) {
                    PurchasedItemEditorView(
                        item: Binding(
                            get: { purchasedItems[index] },
                            set: { purchasedItems[index] = $0 }
                        ),
                        currencyCode: currencyCode,
                        currencySymbol: currencySymbol
                    )
                } else {
                    Text("Item not found")
                        .foregroundStyle(.secondary)
                        .onAppear { editingPurchasedItemID = nil }
                }
            }
        }
        .sheet(item: $transferBaseTransaction) { base in
            NavigationStack {
                TransferMatchPickerView(
                    base: base,
                    currencyCode: currencyCode,
                    onLinked: { _ in
                        selectedCategory = nil
                    },
                    onMarkedUnmatched: {
                        selectedCategory = nil
                    },
                    onConvertedToStandard: {
                        selectedCategory = nil
                    }
                )
            }
        }
        .sheet(item: $processingReview, onDismiss: {
            dismiss()
        }) { item in
            TransactionProcessingReviewView(
                transaction: item.transaction,
                events: item.events
            )
        }
        .sheet(isPresented: $showingReceiptScanner) {
            ReceiptScannerView { image in
                scannedImage = image
                Task {
                    await processReceipt(image)
                }
            }
        }
        .sheet(isPresented: $showingReceiptReview) {
            if let scannedImage, let parsedReceipt {
                ReceiptReviewView(
                    image: scannedImage,
                    parsedReceipt: parsedReceipt,
                    onConfirm: { receipt, selectedItemIds in
                        handleReceiptConfirmed(receipt: receipt, selectedItemIds: selectedItemIds)
                    }
                )
            }
        }
    }

    private func processReceipt(_ image: UIImage) async {
        do {
            let text = try await ReceiptOCRService.recognizeText(from: image)
            parsedReceipt = ReceiptOCRService.parseReceipt(from: text)
            showingReceiptReview = true
        } catch {
            // OCR failed, show review with empty data
            parsedReceipt = ReceiptOCRService.ParsedReceipt(
                merchant: nil,
                date: nil,
                total: nil,
                items: [],
                rawText: ""
            )
            showingReceiptReview = true
        }
    }

    private func handleReceiptConfirmed(receipt: ReceiptImage, selectedItemIds: Set<UUID>) {
        receiptImage = receipt

        // Add selected items to purchased items
        for item in receipt.items where selectedItemIds.contains(item.id) {
            if canAddPurchasedItem {
                let totalPrice = item.price * Decimal(item.quantity)
                let note = item.quantity > 1 ? "\(item.quantity)x @ \(item.price.formatted(.currency(code: currencyCode)))" : ""
                purchasedItems.append(PurchasedItemDraft(
                    id: UUID(),
                    name: item.name,
                    price: totalPrice,
                    note: note
                ))
            }
        }

        // Optionally update transaction fields if they're empty
        if payee.isEmpty, let merchant = receipt.merchant {
            payee = merchant
        }
        if let receiptDate = receipt.receiptDate, date == Date() {
            date = receiptDate
        }
        if amount == 0, let total = receipt.totalAmount {
            amountType = .expense
            amount = -abs(total)
            amountInput = String(format: "%.2f", NSDecimalNumber(decimal: abs(total)).doubleValue)
        }
    }

    private var placeholderSelectorLabel: some View {
        Capsule()
            .fill(Color(.secondarySystemFill))
            .frame(height: 36)
            .overlay(
                HStack(spacing: 6) {
                    Text("Select")
                    Image(systemName: "chevron.down")
                        .appCaptionText()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        .allowsHitTesting(false)
    }
    
    private func resetNewAccountForm() {
        newAccountName = ""
        newAccountBalanceInput = ""
        newAccountType = .chequing
        showingNewAccountSheet = false
    }
    
    private func createNewAccountFromSheet() {
        let balance = decimalFromInput(newAccountBalanceInput)
        let newAccount = Account(name: newAccountName.trimmingCharacters(in: .whitespaces), type: newAccountType, balance: balance)
        modelContext.insert(newAccount)
        selectedAccount = newAccount
        resetNewAccountForm()
    }
    
    private func resetNewCategoryForm() {
        newCategoryName = ""
        newCategoryGroup = nil
        showingNewCategorySheet = false
        categoryCreationStep = .groupSelection
    }
    
    private func createNewCategoryFromSheet() {
        guard let group = newCategoryGroup ?? categoryGroups.first else { return }
        let category = Category(name: newCategoryName.trimmingCharacters(in: .whitespaces))
        category.group = group
        modelContext.insert(category)
        selectedCategory = category
        resetNewCategoryForm()
    }
    
    private func resetNewGroupForm() {
        newGroupName = ""
        newGroupType = .expense
        showingNewGroupSheet = false
    }
    
    private func createNewGroupFromSheet() {
        let group = CategoryGroup(name: newGroupName.trimmingCharacters(in: .whitespaces), type: newGroupType)
        modelContext.insert(group)
        newCategoryGroup = group
        categoryCreationStep = .details
        resetNewGroupForm()
    }

    @ViewBuilder
    private func transferInformationContent(for transaction: Transaction) -> some View {
        // Check if transaction is marked as external transfer
        if let externalLabel = transaction.externalTransferLabel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("External Transfer")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Text(externalLabel)
                            .appSecondaryBodyText()
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.tint(for: appColorMode))
                }
                .padding()
                .background(AppColors.tint(for: appColorMode).opacity(0.1))
                .cornerRadius(AppTheme.Radius.button)

                Button(role: .destructive) {
                    clearExternalTransferLabel(transaction)
                } label: {
                    Label("Remove External Label", systemImage: "xmark.circle")
                        .appSecondaryBodyText()
                        .frame(maxWidth: .infinity)
                }
                .appSecondaryCTA()
            }
        } else if let transferID = transaction.transferID {
            // Show matched transfer info
            VStack(alignment: .leading, spacing: 12) {
                if let matched = fetchMatchedTransfer(transferID: transferID, excluding: transaction.persistentModelID) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Matched Transfer")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("\(transaction.account?.name ?? "Account") → \(matched.account?.name ?? "Account")")
                                .appSecondaryBodyText()
                                .fontWeight(.medium)
                            Text(matched.payee)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(matched.amount, format: .currency(code: currencyCode))
                            .appSecondaryBodyText()
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding()
                    .background(AppColors.tint(for: appColorMode).opacity(0.1))
                    .cornerRadius(AppTheme.Radius.button)

                    Button(role: .destructive) {
                        unmatchTransfer(transaction)
                    } label: {
                        Label("Unmatch Transfer", systemImage: "link.badge.minus")
                            .appSecondaryBodyText()
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryCTA()
                } else {
                    Text("Previously matched transfer no longer available")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // Show Find Match button for unmatched transfers
            VStack(alignment: .leading, spacing: 12) {
                Text("This transaction is marked as a transfer but not yet matched with a corresponding transaction in another account.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)

                Button {
                    transferBaseTransaction = transaction
                } label: {
                    Label("Find Match", systemImage: "magnifyingglass")
                        .appSecondaryBodyText()
                        .frame(maxWidth: .infinity)
                }
                .appPrimaryCTA()
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private func fetchMatchedTransfer(transferID: UUID, excluding: PersistentIdentifier) -> Transaction? {
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first { $0.persistentModelID != excluding }
    }

    private func unmatchTransfer(_ transaction: Transaction) {
        guard let transferID = transaction.transferID else { return }

        let oldSnapshot = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)

        // Find and unmatch the paired transaction
        if let matched = fetchMatchedTransfer(transferID: transferID, excluding: transaction.persistentModelID) {
            let matchedOldSnapshot = TransactionSnapshot(from: matched)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: matchedOldSnapshot)

            matched.transferID = nil
            matched.transferInboxDismissed = false
            matched.kind = .standard
            matched.category = nil

            logHistory(for: matched, detail: "Unmatched from transfer pair and converted to standard transaction.")
            TransactionStatsUpdateCoordinator.markDirty(transaction: matched)
        }

        // Unmatch this transaction
        transaction.transferID = nil
        transaction.transferInboxDismissed = false

        logHistory(for: transaction, detail: "Unmatched from transfer pair.")
        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

        // Save changes
        _ = modelContext.safeSave(context: "TransactionFormView.unmatchTransfer")
    }

	    private func clearExternalTransferLabel(_ transaction: Transaction) {
            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
	        let oldLabel = transaction.externalTransferLabel
	        transaction.externalTransferLabel = nil
	        transaction.transferInboxDismissed = false

        if let label = oldLabel {
            logHistory(for: transaction, detail: "Removed external transfer label: \(label).")
        }

        _ = modelContext.safeSave(context: "TransactionFormView.clearExternalTransferLabel")
    }

	    private func convertAndShowTransferPicker(_ transaction: Transaction) {
            let oldSnapshot = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)

	        // Convert standard transaction to transfer if needed
	        if transaction.kind == .standard {
	            transaction.kind = .transfer
	            transaction.category = nil
            transaction.transferID = nil
            transaction.transferInboxDismissed = false

            // Update the state variables to match the transaction changes
            transactionKind = .transfer
            selectedCategory = nil

            logHistory(for: transaction, detail: "Converted from Standard to Transfer.")
	
	            // Save the conversion
                TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
	            guard modelContext.safeSave(context: "TransactionFormView.convertAndShowTransferPicker") else {
	                return
	            }
	        }

        // Open the transfer matching UI
        transferBaseTransaction = transaction
    }

	    private func saveTransaction() {
        if isSplit && splitTotal != amount {
            validationMessage = "Split amounts must equal the total transaction amount."
            showingValidationAlert = true
            return
        }

        var savedTransaction: Transaction?

	        if let transaction = transactionToEdit {
            let oldPurchasedItems: [PurchasedItemSnapshot] = (transaction.purchasedItems ?? [])
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .map { item in
                    PurchasedItemSnapshot(
                        id: item.persistentModelID,
                        name: item.name,
                        price: item.price,
                        note: item.note,
                        order: item.order
                    )
                }

            // Handle Account Change or Amount Change
	            let oldAmount = transaction.amount
	            let oldAccount = transaction.account
	            let oldCategory = transaction.category
	            let oldKind = transaction.kind
	            let oldTransferID = transaction.transferID
	            let oldPayee = transaction.payee
	            let oldDate = transaction.date
	            let oldMemo = transaction.memo
	            let wasSplit = !(transaction.subtransactions ?? []).isEmpty
                let oldSnapshot = TransactionSnapshot(from: transaction)
                TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)
            
	            // Update properties
	            transaction.payee = payee
	            transaction.amount = amount
	            transaction.date = date
            transaction.memo = TransactionTextLimits.normalizedMemo(memo)
            transaction.account = selectedAccount
            transaction.category = selectedCategory
            transaction.tags = selectedTags
            transaction.kind = transactionKind
            // Clear transferID when converting away from transfer
            if transactionKind != .transfer {
                transaction.transferID = nil
            }

            // If we’re breaking a linked transfer pair, also clear the other side’s transferID
            // so it becomes an unmatched transfer (and can be re-linked in the Transfers inbox).
            if oldKind == .transfer, transactionKind != .transfer, let oldTransferID {
                let id: UUID? = oldTransferID
                let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
                let matches = (try? modelContext.fetch(descriptor)) ?? []
                for match in matches where match.persistentModelID != transaction.persistentModelID {
                    match.transferID = nil
                    match.transferInboxDismissed = false
                }
            }
            
            // Update Balances
            if oldAccount == selectedAccount {
                // Same account, just diff
                if let account = selectedAccount {
                    account.balance += (amount - oldAmount)
                }
            } else {
                // Account changed
                if let old = oldAccount {
                    old.balance -= oldAmount
                }
                if let new = selectedAccount {
                    new.balance += amount
                }
            }
            
            if isSplit {
                transaction.kind = .standard
                transaction.transferID = nil
                transaction.category = nil
                // Update subtransactions
                // Delete old subs
                if let oldSubs = transaction.subtransactions {
                    for sub in oldSubs {
                        modelContext.delete(sub)
                    }
                }
                // Create new subs
                for subData in subtransactions {
                    let sub = Transaction(date: date, payee: payee, amount: subData.amount, memo: TransactionTextLimits.normalizedMemo(subData.memo), account: selectedAccount, category: subData.category, parentTransaction: transaction, tags: selectedTags)
                    modelContext.insert(sub)
                }
            } else {
                // Remove any old subs
                if let oldSubs = transaction.subtransactions {
                    for sub in oldSubs {
                        modelContext.delete(sub)
                    }
                }
            }
            
            recordChanges(
                for: transaction,
                oldAmount: oldAmount,
                oldAccount: oldAccount,
                oldCategory: oldCategory,
                oldPayee: oldPayee,
                oldDate: oldDate,
                oldMemo: oldMemo,
                wasSplit: wasSplit
            )

            let limitedDrafts = purchasedItems.prefix(TransactionTextLimits.maxPurchasedItemsPerTransaction)
            recordPurchasedItemChanges(for: transaction, oldItems: oldPurchasedItems, newDrafts: limitedDrafts)
	            syncPurchasedItems(into: transaction)
	            syncReceipt(into: transaction)
                TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
	            savedTransaction = transaction
	        } else {
            // Create new
	            let newTransaction = Transaction(
                date: date,
                payee: payee,
                amount: amount,
                memo: TransactionTextLimits.normalizedMemo(memo),
                status: .uncleared,
                kind: (isSplit ? .standard : transactionKind),
                transferID: nil,  // Always nil - transfers are matched separately via TransferLinker
                account: selectedAccount,
                category: (isSplit || transactionKind == .transfer) ? nil : selectedCategory,
                tags: selectedTags
            )
	            modelContext.insert(newTransaction)
                TransactionStatsUpdateCoordinator.markDirty(transaction: newTransaction)
	            
	            if let account = selectedAccount {
	                account.balance += amount
	            }

            syncPurchasedItems(into: newTransaction)
            syncReceipt(into: newTransaction)
            if isSplit {
                for subData in subtransactions {
                    let sub = Transaction(date: date, payee: payee, amount: subData.amount, memo: TransactionTextLimits.normalizedMemo(subData.memo), account: selectedAccount, category: subData.category, parentTransaction: newTransaction, tags: selectedTags)
                    modelContext.insert(sub)
                }
                logHistory(for: newTransaction, detail: "Transaction created and split into \(subtransactions.count) part\(subtransactions.count == 1 ? "" : "s").")
            } else {
                if let category = selectedCategory {
                    logHistory(for: newTransaction, detail: "Transaction created in category \(category.name).")
                } else {
                logHistory(for: newTransaction, detail: "Transaction created.")
                }
            }

            savedTransaction = newTransaction
        }

        // Save changes with error handling
        let saveSuccessful = modelContext.safeSave(
            context: "TransactionFormView.saveTransaction",
            userTitle: "Error Saving Transaction",
            userMessage: "Couldn't save the transaction. Please try again.",
            showErrorToUser: true
        )

        guard saveSuccessful else { return }
        guard let savedTransaction else {
            dismiss()
            return
        }

        if savedTransaction.kind == .standard, savedTransaction.category != nil {
            AutoRulesService(modelContext: modelContext).learnFromCategorization(transaction: savedTransaction, wasAutoDetected: false)
        }

        if isSplit || savedTransaction.parentTransaction != nil || !(savedTransaction.subtransactions ?? []).isEmpty {
            dismiss()
            return
        }

        let originalPayeeByID: [PersistentIdentifier: String] = [
            savedTransaction.persistentModelID: savedTransaction.payee
        ]

        let processingResult = TransactionProcessor.process(
            transactions: [savedTransaction],
            in: modelContext,
            source: .manual,
            originalPayeeByTransactionID: originalPayeeByID
        )

        let postSaveSuccessful = modelContext.safeSave(
            context: "TransactionFormView.saveTransaction.postProcess",
            userTitle: "Error Applying Rules",
            userMessage: "The transaction was saved, but automatic processing couldn't be applied.",
            showErrorToUser: true
        )

        guard postSaveSuccessful else { return }

        let events = processingResult.eventsByTransactionID[savedTransaction.persistentModelID] ?? []
        if events.isEmpty {
            dismiss()
            return
        }

        processingReview = ProcessingReviewSheetItem(
            transaction: savedTransaction,
            events: events
        )
    }
    
    private func toggleNegativeForFocusedField() {
        switch focusedField {
        case .amount:
            amount *= -1
            amountInput = TransactionFormView.plainAmountInput(for: amount)
            amountType = amount >= 0 ? .income : .expense
            enforceSplitSigns()
        case .splitAmount(let id):
            if let index = subtransactions.firstIndex(where: { $0.id == id }) {
                subtransactions[index].amount *= -1
            }
        default:
            break
        }
    }
    
    private func removeSplit() {
        guard let transaction = transactionToEdit, let parent = transaction.parentTransaction else { return }
        if let children = parent.subtransactions {
            for child in children {
                modelContext.delete(child)
            }
        }
        parent.subtransactions = []
        parent.category = nil
        logHistory(for: parent, detail: "Split removed from transaction.")
        showingRemoveSplitConfirmation = false

        let saveSuccessful = modelContext.safeSave(
            context: "TransactionFormView.removeSplit",
            userTitle: "Error Removing Split",
            userMessage: "Couldn't remove the split. Please try again.",
            showErrorToUser: true
        )

        if saveSuccessful {
            dismiss()
        }
    }

    private func deleteTransaction() {
        guard let transaction = transactionToEdit else { return }

        // Update account balance
        if let account = transaction.account {
            account.balance -= transaction.amount
        }

        // Delete any subtransactions if this is a parent
        if let children = transaction.subtransactions {
            for child in children {
                modelContext.delete(child)
            }
        }

        // Use undo/redo manager if available
        do {
            try undoRedoManager.execute(
                DeleteTransactionCommand(modelContext: modelContext, transaction: transaction)
            )
        } catch {
            // Fallback to direct delete if command fails
            modelContext.delete(transaction)
        }

        let saveSuccessful = modelContext.safeSave(
            context: "TransactionFormView.deleteTransaction",
            userTitle: "Error Deleting Transaction",
            userMessage: "Couldn't delete the transaction. Please try again.",
            showErrorToUser: true
        )

        if saveSuccessful {
            dismiss()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func addPurchasedItem() {
        guard canAddPurchasedItem else { return }
        let newItem = PurchasedItemDraft()
        purchasedItems.append(newItem)
        editingPurchasedItemID = newItem.id
    }

    private func deletePurchasedItems(at offsets: IndexSet) {
        if let editingPurchasedItemID,
           let index = purchasedItems.firstIndex(where: { $0.id == editingPurchasedItemID }),
           offsets.contains(index) {
            self.editingPurchasedItemID = nil
        }
        purchasedItems.remove(atOffsets: offsets)
    }

    private func syncPurchasedItems(into transaction: Transaction) {
        let limitedDrafts = purchasedItems.prefix(TransactionTextLimits.maxPurchasedItemsPerTransaction)

        let existing = transaction.purchasedItems ?? []
        var existingByID: [PersistentIdentifier: PurchasedItem] = [:]
        existingByID.reserveCapacity(existing.count)
        for item in existing {
            existingByID[item.persistentModelID] = item
        }

        let keepIDs = Set(limitedDrafts.compactMap(\.modelID))
        for existingItem in existing where !keepIDs.contains(existingItem.persistentModelID) {
            modelContext.delete(existingItem)
        }

        for (index, draft) in limitedDrafts.enumerated() {
            let name = TransactionTextLimits.normalizedPurchasedItemName(draft.name)
            let note = TransactionTextLimits.normalizedPurchasedItemNote(draft.note)

            if let modelID = draft.modelID, let existingItem = existingByID[modelID] {
                existingItem.name = name
                existingItem.price = draft.price
                existingItem.note = note
                existingItem.order = index
            } else {
                let newItem = PurchasedItem(
                    name: name,
                    price: draft.price,
                    note: note,
                    order: index,
                    transaction: transaction,
                    isDemoData: transaction.isDemoData
                )
                modelContext.insert(newItem)
            }
        }
    }

    private func syncReceipt(into transaction: Transaction) {
        if let receiptImage {
            // If there's a new receipt, insert or update it
            if transaction.receipt == nil {
                // Insert new receipt
                modelContext.insert(receiptImage)
                transaction.receipt = receiptImage
            } else {
                // Update existing receipt
                transaction.receipt?.imageData = receiptImage.imageData
                transaction.receipt?.extractedText = receiptImage.extractedText
                transaction.receipt?.items = receiptImage.items
                transaction.receipt?.totalAmount = receiptImage.totalAmount
                transaction.receipt?.merchant = receiptImage.merchant
                transaction.receipt?.receiptDate = receiptImage.receiptDate
            }
        } else {
            // Remove receipt if it was deleted
            if let existingReceipt = transaction.receipt {
                modelContext.delete(existingReceipt)
                transaction.receipt = nil
            }
        }
    }
}

private struct PurchasedItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    @Binding var item: TransactionFormView.PurchasedItemDraft
    let currencyCode: String
    let currencySymbol: String

    @Query(sort: \PurchasedItem.name) private var allPurchasedItems: [PurchasedItem]

    private var noteLimit: Int { TransactionTextLimits.maxPurchasedItemNoteLength }
    private var nameLimit: Int { TransactionTextLimits.maxPurchasedItemNameLength }

    private var nameSuggestions: [String] {
        let needle = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }

        let lowerNeedle = needle.lowercased()
        let candidates = Set(allPurchasedItems.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .filter { $0.lowercased() != lowerNeedle }
            .filter { $0.localizedCaseInsensitiveContains(needle) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return Array(candidates.prefix(8))
    }

    var body: some View {
        Form {
            Section("Item") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    TextField("Item name", text: $item.name)
                        .onChange(of: item.name) { _, newValue in
                            guard newValue.count > nameLimit else { return }
                            item.name = String(newValue.prefix(nameLimit))
                        }

                    if !nameSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(nameSuggestions.enumerated()), id: \.element) { index, suggestion in
                                Button {
                                    item.name = suggestion
                                } label: {
                                    HStack {
                                        Text(suggestion)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                if index != nameSuggestions.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                                .fill(Color(.secondarySystemFill))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous))
                    }

                    HStack {
                        Spacer()
                        Text("\(min(item.name.count, nameLimit))/\(nameLimit)")
                            .font(.caption2)
                            .foregroundStyle(item.name.count >= nameLimit ? AppColors.warning(for: appColorMode) : .secondary)
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Price")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $item.priceInput)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .onChange(of: item.priceInput) { _, newValue in
                                item.price = TransactionFormView.decimalFromInput(newValue)
                            }
                    }
                }
            }

            Section("Note") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Optional note", text: $item.note, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: item.note) { _, newValue in
                            guard newValue.count > noteLimit else { return }
                            item.note = String(newValue.prefix(noteLimit))
                        }

                    HStack {
                        Spacer()
                        Text("\(min(item.note.count, noteLimit))/\(noteLimit)")
                            .font(.caption2)
                            .foregroundStyle(item.note.count >= noteLimit ? AppColors.warning(for: appColorMode) : .secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Purchase Item")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            item.name = TransactionTextLimits.normalizedPurchasedItemName(item.name)
        }
        .onDisappear {
            item.name = TransactionTextLimits.normalizedPurchasedItemName(item.name)
            item.note = TransactionTextLimits.normalizedPurchasedItemNote(item.note) ?? ""
        }
    }
}

private extension TransactionFormView {
    static func decimalFromInput(_ input: String) -> Decimal {
        let sanitized = input
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Decimal(string: sanitized) ?? 0
    }
}
