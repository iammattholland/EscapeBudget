import Foundation
import SwiftUI
import SwiftData

struct BulkCategorizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    let transactions: [Transaction]
    let categoryGroups: [CategoryGroup]
    let onCategorized: ([Transaction]) -> Void

    @State private var selectedCategory: Category?
    @State private var filterType: FilterType = .payeeExact
    @State private var filterValue: String = ""
    @State private var amountMin: String = ""
    @State private var amountMax: String = ""
    @State private var selectedAccount: Account?
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()
    @State private var matchingTransactions: [Transaction] = []
    @State private var showingPreview = false
    @State private var recentPayees: [String] = []
    @State private var suggestedPayeeOptions: [SuggestedPayeeOption] = []
    @State private var selectedSuggestedOption: SuggestedPayeeOption?

    @Query private var accounts: [Account]

    enum FilterType: String, CaseIterable, Identifiable {
        case payeeExact = "Payee (Exact Match)"
        case payeeContains = "Payee (Contains)"
        case amountExact = "Amount (Exact)"
        case amountRange = "Amount (Range)"
        case account = "Account"
        case dateRange = "Date Range"
        case combined = "Multiple Criteria"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Category") {
                    Menu {
                        ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                            Menu(group.name) {
                                ForEach(group.sortedCategories) { category in
                                    Button(category.name) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Category")
                            Spacer()
                            if let category = selectedCategory {
                                Text(category.name)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Select...")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Filter Criteria") {
                    Picker("Filter By", selection: $filterType) {
                        ForEach(FilterType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    switch filterType {
                    case .payeeExact, .payeeContains:
                        TextField("Payee Name", text: $filterValue)
                            .autocorrectionDisabled()
                        if !payeeSuggestions.isEmpty {
                            payeeSuggestionsRow
                        }
                        Text("Finds transactions with payee name that \(filterType == .payeeExact ? "exactly matches" : "contains") the text above")
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                    case .amountExact:
                        HStack(spacing: AppTheme.Spacing.compact) {
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                            TextField("Amount", text: $filterValue)
                                .keyboardType(.decimalPad)
                        }
                        Text("Finds transactions with this exact amount")
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                    case .amountRange:
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            HStack(spacing: AppTheme.Spacing.compact) {
                                Text("Min:")
                                    .foregroundStyle(.secondary)
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: $amountMin)
                                    .keyboardType(.decimalPad)
                            }

                            HStack(spacing: AppTheme.Spacing.compact) {
                                Text("Max:")
                                    .foregroundStyle(.secondary)
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: $amountMax)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        Text("Finds transactions within this amount range")
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                    case .account:
                        Picker("Account", selection: $selectedAccount) {
                            Text("Any Account").tag(nil as Account?)
                            ForEach(accounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        Text("Finds transactions from the selected account")
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                    case .dateRange:
                        DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("To", selection: $dateTo, displayedComponents: .date)
                        Text("Finds transactions within this date range")
                            .appCaptionText()
                            .foregroundStyle(.secondary)

                    case .combined:
                        TextField("Payee (optional)", text: $filterValue)
                            .autocorrectionDisabled()
                        if !payeeSuggestions.isEmpty {
                            payeeSuggestionsRow
                        }

                        Picker("Account (optional)", selection: $selectedAccount) {
                            Text("Any Account").tag(nil as Account?)
                            ForEach(accounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            Text("Amount Range (optional)")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            HStack(spacing: AppTheme.Spacing.compact) {
                                Text("Min:")
                                    .foregroundStyle(.secondary)
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: $amountMin)
                                    .keyboardType(.decimalPad)
                            }

                            HStack(spacing: AppTheme.Spacing.compact) {
                                Text("Max:")
                                    .foregroundStyle(.secondary)
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: $amountMax)
                                    .keyboardType(.decimalPad)
                            }
                        }

                        DatePicker("From (optional)", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("To (optional)", selection: $dateTo, displayedComponents: .date)

                        Text("Combines multiple criteria - all specified filters must match")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        findMatchingTransactions()
                        showingPreview = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Preview Matches")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(selectedCategory == nil)
                } footer: {
                    if !matchingTransactions.isEmpty {
                        Text("Found \(matchingTransactions.count) matching transaction\(matchingTransactions.count == 1 ? "" : "s")")
                            .foregroundStyle(AppColors.success(for: appColorMode))
                    }
                }

                Section {
                    if suggestedPayeeOptions.isEmpty {
                        Text("No suggested payee groupings yet.")
                            .foregroundStyle(.secondary)
                    } else {
	                        ForEach(suggestedPayeeOptions) { option in
	                            Button {
	                                selectedSuggestedOption = option
	                            } label: {
                                HStack(spacing: AppTheme.Spacing.tight) {
	                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                                        Text(option.payeeDisplay)
	                                            .appSectionTitleText()
	                                            .lineLimit(1)

                                        Text("Suggest: \(option.category.name)")
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

	                                    Text("\(option.transactionIDs.count)")
	                                        .appSectionTitleText()
	                                        .monospacedDigit()
	                                        .foregroundStyle(AppColors.tint(for: appColorMode))

                                    Image(systemName: "chevron.right")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Suggested Options")
                } footer: {
                    Text("Based on your already categorized transactions, Escape Budget suggests a category for uncategorized transactions with the same (or similar) payee name.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bulk Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPreview) {
                BulkCategorizePreviewView(
                    transactions: matchingTransactions,
                    category: selectedCategory!,
                    currencyCode: currencyCode,
                    onConfirm: {
                        applyBulkCategorization()
                    }
                )
            }
            .sheet(item: $selectedSuggestedOption) { option in
                SuggestedPayeeCategorizeSheet(
                    option: option,
                    currencyCode: currencyCode,
                    onApplied: { updated in
                        onCategorized(updated)
                        refreshSuggestedPayeeOptions()
                    }
                )
            }
        }
        .onAppear {
            loadRecentPayees()
            refreshSuggestedPayeeOptions()
        }
    }

    private var payeeSuggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ForEach(payeeSuggestions, id: \.self) { suggestion in
                    Button {
                        filterValue = suggestion
                    } label: {
                        Text(suggestion)
                            .lineLimit(1)
                    }
                    .appSecondaryCTA()
                    .controlSize(.small)
                }
            }
            .padding(.vertical, AppTheme.Spacing.hairline)
        }
    }

    private var payeeSuggestions: [String] {
        let needle = filterValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        guard filterType == .payeeExact || filterType == .payeeContains || filterType == .combined else { return [] }

        let candidates = transactions.map(\.payee) + recentPayees
        var counts: [String: Int] = [:]
        var canonical: [String: String] = [:]

        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            counts[key, default: 0] += 1
            // Prefer the most recently seen formatting (recentPayees is already recent-first).
            if canonical[key] == nil {
                canonical[key] = trimmed
            }
        }

        let filteredKeys = counts.keys.filter { $0.contains(needle.lowercased()) }
        let sorted = filteredKeys.sorted { lhs, rhs in
            let lc = counts[lhs, default: 0]
            let rc = counts[rhs, default: 0]
            if lc != rc { return lc > rc }
            return (canonical[lhs] ?? lhs).localizedCaseInsensitiveCompare(canonical[rhs] ?? rhs) == .orderedAscending
        }

        return sorted.prefix(8).compactMap { canonical[$0] }
    }

    private func loadRecentPayees() {
        do {
            var descriptor = FetchDescriptor<Transaction>(
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            let fetched: [Transaction] = try modelContext.fetch(descriptor)

            // Keep duplicates for frequency scoring, but trim empties.
            recentPayees = fetched
                .map(\.payee)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            recentPayees = []
        }
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    private func findMatchingTransactions() {
        matchingTransactions = transactions.filter { transaction in
            switch filterType {
            case .payeeExact:
                return !filterValue.isEmpty && transaction.payee.lowercased() == filterValue.lowercased()

            case .payeeContains:
                return !filterValue.isEmpty && transaction.payee.lowercased().contains(filterValue.lowercased())

            case .amountExact:
                guard let targetAmount = Decimal(string: filterValue.replacingOccurrences(of: ",", with: "")) else {
                    return false
                }
                return abs(transaction.amount) == abs(targetAmount)

            case .amountRange:
                let min = Decimal(string: amountMin.replacingOccurrences(of: ",", with: ""))
                let max = Decimal(string: amountMax.replacingOccurrences(of: ",", with: ""))
                let absAmount = abs(transaction.amount)

                if let min = min, let max = max {
                    return absAmount >= min && absAmount <= max
                } else if let min = min {
                    return absAmount >= min
                } else if let max = max {
                    return absAmount <= max
                }
                return false

            case .account:
                guard let account = selectedAccount else { return false }
                return transaction.account?.persistentModelID == account.persistentModelID

            case .dateRange:
                return transaction.date >= dateFrom && transaction.date <= dateTo

            case .combined:
                // All specified criteria must match
                var matches = true

                // Check payee if specified
                if !filterValue.isEmpty {
                    matches = matches && transaction.payee.lowercased().contains(filterValue.lowercased())
                }

                // Check account if specified
                if let account = selectedAccount {
                    matches = matches && transaction.account?.persistentModelID == account.persistentModelID
                }

                // Check amount range if specified
                let min = Decimal(string: amountMin.replacingOccurrences(of: ",", with: ""))
                let max = Decimal(string: amountMax.replacingOccurrences(of: ",", with: ""))
                let absAmount = abs(transaction.amount)

                if let min = min {
                    matches = matches && absAmount >= min
                }
                if let max = max {
                    matches = matches && absAmount <= max
                }

                // Check date range
                matches = matches && transaction.date >= dateFrom && transaction.date <= dateTo

                return matches
            }
        }
    }

    private func applyBulkCategorization() {
        guard let category = selectedCategory else { return }

        let previousCategories = matchingTransactions.map { (transaction: $0, category: $0.category) }
        for transaction in matchingTransactions {
            let oldSnapshot = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)
            transaction.category = category
            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

            TransactionHistoryService.append(
                detail: "Bulk categorized to \(category.name).",
                to: transaction,
                in: modelContext
            )

            if transaction.kind == .standard {
                AutoRulesService(modelContext: modelContext).learnFromCategorization(transaction: transaction, wasAutoDetected: false)
            }
        }

        guard modelContext.safeSave(context: "BulkCategorizeView.applyBulkCategorization") else {
            for previous in previousCategories {
                previous.transaction.category = previous.category
            }
            return
        }
        onCategorized(matchingTransactions)
        dismiss()
    }

    private func payeeSuggestionKey(_ payee: String) -> String {
        var key = PayeeNormalizer.normalizeForComparison(payee)
        key = key.replacingOccurrences(of: "[0-9]", with: "", options: .regularExpression)
        key = key
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key
    }

    private func refreshSuggestedPayeeOptions() {
        // Use only transactions visible to this bulk flow so the suggestions align with what the user can act on.
        var categoryLookup: [PersistentIdentifier: Category] = [:]
        var categoryCountsByPayeeKey: [String: [PersistentIdentifier: Int]] = [:]

        for transaction in transactions {
            guard transaction.kind == .standard, let category = transaction.category else { continue }
            let key = payeeSuggestionKey(transaction.payee)
            guard !key.isEmpty else { continue }

            let categoryID = category.persistentModelID
            categoryLookup[categoryID] = category
            categoryCountsByPayeeKey[key, default: [:]][categoryID, default: 0] += 1
        }

        var uncategorizedGroups: [String: [Transaction]] = [:]
        for transaction in transactions where transaction.isUncategorized {
            let key = payeeSuggestionKey(transaction.payee)
            guard !key.isEmpty else { continue }
            uncategorizedGroups[key, default: []].append(transaction)
        }

        var options: [SuggestedPayeeOption] = []
        options.reserveCapacity(uncategorizedGroups.count)

        for (key, group) in uncategorizedGroups {
            guard group.count >= 2 else { continue }
            guard let counts = categoryCountsByPayeeKey[key], !counts.isEmpty else { continue }
            guard let (bestCategoryID, _) = counts.max(by: { $0.value < $1.value }) else { continue }
            guard let suggestedCategory = categoryLookup[bestCategoryID] else { continue }

            let representative = PayeeNormalizer.normalizeDisplay(group[0].payee)
            let sortedIDs = group
                .sorted { $0.date > $1.date }
                .map(\.persistentModelID)

            options.append(
                SuggestedPayeeOption(
                    id: "\(key)|\(bestCategoryID)",
                    payeeKey: key,
                    payeeDisplay: representative,
                    category: suggestedCategory,
                    transactionIDs: sortedIDs
                )
            )
        }

        suggestedPayeeOptions = options
            .sorted {
                if $0.transactionIDs.count != $1.transactionIDs.count { return $0.transactionIDs.count > $1.transactionIDs.count }
                return $0.payeeDisplay.localizedCaseInsensitiveCompare($1.payeeDisplay) == .orderedAscending
            }
            .prefix(10)
            .map { $0 }
    }
}

private struct SuggestedPayeeOption: Identifiable {
    let id: String
    let payeeKey: String
    let payeeDisplay: String
    let category: Category
    let transactionIDs: [PersistentIdentifier]
}

private struct SuggestedPayeeCategorizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    let option: SuggestedPayeeOption
    let currencyCode: String
    let onApplied: ([Transaction]) -> Void

    @State private var selectedIDs: Set<PersistentIdentifier>
    @State private var transactions: [Transaction] = []

    init(option: SuggestedPayeeOption, currencyCode: String, onApplied: @escaping ([Transaction]) -> Void) {
        self.option = option
        self.currencyCode = currencyCode
        self.onApplied = onApplied
        _selectedIDs = State(initialValue: Set(option.transactionIDs))
    }

    var body: some View {
        NavigationStack {
            List {
	                Section {
	                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
	                        Text(option.payeeDisplay)
	                            .appSectionTitleText()
	                        Text("Suggested category: \(option.category.name)")
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)
	                    }
	                    .padding(.vertical, AppTheme.Spacing.micro)
	                }

                Section {
                    if transactions.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "tray",
                            description: Text("These transactions may have been deleted or moved.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(transactions) { transaction in
                            let id = transaction.persistentModelID
                            Button {
                                if selectedIDs.contains(id) { selectedIDs.remove(id) }
                                else { selectedIDs.insert(id) }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.tight) {
                                    Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(id) ? AppColors.tint(for: appColorMode) : .secondary)

	                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
	                                        Text(transaction.payee)
	                                            .appSectionTitleText()
	                                            .lineLimit(1)
	                                        Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
	                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(transaction.amount, format: .currency(code: currencyCode))
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Tap to unselect any transactions you don’t want included in this categorization.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Suggested Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .task {
                loadTransactions()
            }
        }
    }

    private func loadTransactions() {
        transactions = option.transactionIDs.compactMap { id in
            modelContext.model(for: id) as? Transaction
        }
        .sorted { $0.date > $1.date }
    }

	    private func apply() {
	        let selectedTransactions = selectedIDs.compactMap { id in
	            modelContext.model(for: id) as? Transaction
	        }
	        guard !selectedTransactions.isEmpty else { return }
	
	        let previousCategories = selectedTransactions.map { (transaction: $0, category: $0.category) }
	        for transaction in selectedTransactions {
                let oldSnapshot = TransactionSnapshot(from: transaction)
                TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)
	            transaction.category = option.category
                TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

                TransactionHistoryService.append(
                    detail: "Bulk categorized to \(option.category.name) (suggested payee).",
                    to: transaction,
                    in: modelContext
                )

                if transaction.kind == .standard {
                    AutoRulesService(modelContext: modelContext).learnFromCategorization(transaction: transaction, wasAutoDetected: false)
                }
	        }
	
	        guard modelContext.safeSave(context: "SuggestedPayeeCategorizeSheet.apply") else {
	            for previous in previousCategories {
	                previous.transaction.category = previous.category
	            }
	            return
	        }

        onApplied(selectedTransactions)
        dismiss()
    }
}

struct BulkCategorizePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    let transactions: [Transaction]
    let category: Category
    let currencyCode: String
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.medium) {
                // Summary Card
                VStack(spacing: AppTheme.Spacing.tight) {
                    Image(systemName: "checkmark.circle.fill")
                        .appIconXLarge()
                        .foregroundStyle(AppColors.success(for: appColorMode))

                    Text("\(transactions.count) Transaction\(transactions.count == 1 ? "" : "s")")
                        .appTitleText()
                        .fontWeight(.bold)

	                    Text("will be categorized as")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)

                    Text(category.name)
                        .appTitleText()
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.tint(for: appColorMode))
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.compact)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xSmall)
                                .fill(AppColors.tint(for: appColorMode).opacity(0.15))
                        )
                }
                .padding()

                // Transaction List
                List {
	                    ForEach(transactions) { transaction in
	                        HStack {
	                            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                                Text(transaction.payee)
	                                    .appSectionTitleText()

	                                Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
	                                    .appCaptionText()
                                    .foregroundStyle(.secondary)

                                if let account = transaction.account {
                                    Text(account.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(transaction.amount, format: .currency(code: currencyCode))
                                .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Confirm Bulk Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onConfirm()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
