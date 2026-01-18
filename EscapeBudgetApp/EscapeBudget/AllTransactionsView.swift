import SwiftUI
import SwiftData
import os.log

struct TransactionFilter {
    var startDate: Date = Date().addingTimeInterval(-86400 * 30) // Default last 30 days
    var endDate: Date = Date()
    var useDateRange: Bool = false
    var payeeName: String = ""
    var minAmount: String = ""
    var maxAmount: String = ""
    var account: Account?
    var selectedCategoryIDs: Set<PersistentIdentifier> = []
    var includeUncategorized: Bool = false
    var includeIgnored: Bool = false
    var tags: [TransactionTag] = []
	    
    var isActive: Bool {
        useDateRange ||
        !payeeName.isEmpty ||
        !minAmount.isEmpty ||
        !maxAmount.isEmpty ||
        account != nil ||
        !selectedCategoryIDs.isEmpty ||
        includeUncategorized ||
        includeIgnored ||
        !tags.isEmpty
    }
}

struct AllTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager
    @EnvironmentObject private var errorCenter: AppErrorCenter
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("showTransactionTags") private var showTransactionTags = false

    @EnvironmentObject private var navigator: AppNavigator
    @Binding var searchText: String
    @Binding var filter: TransactionFilter
    @State private var selectedTransaction: Transaction?
    @State private var viewingReceipt: ReceiptImage?
    @State private var showingAddTransfer = false
    @State private var showingFilter = false

    // Simplified state - let SwiftData @Query handle fetching
    @State private var uncategorizedCount: Int = 0
    @State private var isBulkEditing = false
    @State private var selectedTransactionIDs: Set<PersistentIdentifier> = []
    @State private var showingBulkEditSheet = false
    @State private var showingAutoRules = false

    // UI state
    @State private var showMonthIndexOverlay = false
    @State private var monthIndexHideWorkItem: DispatchWorkItem?

    init(searchText: Binding<String>, filter: Binding<TransactionFilter>) {
        self._searchText = searchText
        self._filter = filter
    }

    // Sheet/modal state
    @State private var showingAccountPicker = false
    @State private var selectedAccountForImport: Account?
    @State private var showingTransferMatch = false
    @State private var transferBaseTransactionID: PersistentIdentifier?
    @State private var showingTransfersInbox = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget", category: "Transactions")

    // SwiftData @Query - automatically updates when data changes
    @Query(
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var allTransactions: [Transaction]

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \CategoryGroup.name) private var categoryGroups: [CategoryGroup]

    @State private var showingNewCategorySheet = false
    @State private var categoryCreationTransactionID: PersistentIdentifier?
    @State private var newCategoryInitialGroup: CategoryGroup?
    
    private var bannerText: String {
        if uncategorizedCount > 99 {
            return "100+ transactions to categorize"
        }
        return "\(uncategorizedCount) transaction\(uncategorizedCount == 1 ? "" : "s") to categorize"
    }
    
    // MARK: - Computed Filtered Data (replaces manual caching)

    /// Filtered transactions based on search text and filter
    /// This is efficient as it's computed only when accessed and SwiftUI will cache appropriately
    private var filteredTransactions: [Transaction] {
        var result = allTransactions

        // Apply search text filter
        if !searchText.isEmpty {
            result = result.filter { TransactionQueryService.matchesSearch($0, query: searchText) }
        }

        // Apply advanced filter
        if filter.isActive {
            result = result.filter { TransactionQueryService.matchesFilter($0, filter: filter) }
        }

        // Filter out split children - only show parent or leaf transactions
        result = result.filter { transaction in
            transaction.parentTransaction == nil || (transaction.subtransactions ?? []).isEmpty
        }

        return result
    }

    /// Month sections grouped from filtered transactions
    /// Computed property - SwiftUI handles caching automatically
    private var monthSections: [MonthSection] {
        let calendar = Calendar.current
        var grouped: [Date: [Transaction]] = [:]
        grouped.reserveCapacity(36)

        for transaction in filteredTransactions {
            let components = calendar.dateComponents([.year, .month], from: transaction.date)
            let monthDate = calendar.date(from: components) ?? transaction.date
            grouped[monthDate, default: []].append(transaction)
        }

        return grouped.keys.sorted(by: >).map { date in
            let items = (grouped[date] ?? []).sorted { $0.date > $1.date }
            let title = Self.monthTitleFormatter.string(from: date)
            return MonthSection(
                id: title,
                title: title,
                shortTitle: Self.monthShortFormatter.string(from: date).uppercased(),
                transactions: items
            )
        }
    }
	    
    var body: some View {
        mainContent
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("All Transactions")
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .toolbar { toolbarContent }
            .sheet(item: $selectedTransaction, content: transactionSheet)
            .sheet(item: $viewingReceipt) { receipt in
                ReceiptDetailView(receipt: receipt, currencyCode: currencyCode)
            }
            .sheet(isPresented: $showingAddTransfer) { addTransferSheet }
            .sheet(isPresented: $showingTransfersInbox) { transfersInboxSheet }
            .sheet(isPresented: $showingFilter) { filterSheet }
            .sheet(isPresented: $showingNewCategorySheet, onDismiss: resetNewCategoryForm) { newCategorySheet }
            .sheet(isPresented: $showingBulkEditSheet) { bulkEditSheet }
            .sheet(isPresented: $showingAutoRules) { autoRulesSheet }
            .sheet(isPresented: $showingTransferMatch) { transferMatchSheet }
            .sheet(isPresented: $showingAccountPicker) { accountPickerSheet }
            .sheet(isPresented: $navigator.showingUncategorizedTransactions, onDismiss: {
                Task { await refreshUncategorizedCount() }
            }) { uncategorizedSheet }
            .sheet(isPresented: $navigator.showingImportTransactions) { importSheet }
            .onChange(of: showingAccountPicker, handleAccountPickerChange)
            .safeAreaInset(edge: .bottom) {
                if isBulkEditing {
                    bulkEditBar
                }
            }
            .task {
                await refreshUncategorizedCount()
            }
            .refreshable {
                // Refresh uncategorized count when pulling to refresh
                await refreshUncategorizedCount()
            }
    }

	    @ToolbarContentBuilder
	    private var toolbarContent: some ToolbarContent {
	        ToolbarItem(placement: .navigationBarLeading) {
	            if isBulkEditing {
	                Button("Done") { exitBulkEdit() }
	            }
	        }
	        ToolbarItem(placement: .navigationBarTrailing) {
		            Menu {
		                Button {
		                    do { try undoRedoManager.undo() } catch { }
		                } label: {
		                    Label("Undo", systemImage: "arrow.uturn.backward")
		                }
		                .disabled(!undoRedoManager.canUndo)

	                Button {
	                    do { try undoRedoManager.redo() } catch { }
	                } label: {
	                    Label("Redo", systemImage: "arrow.uturn.forward")
	                }
	                .disabled(!undoRedoManager.canRedo)

	                Divider()

		                Button { navigator.addTransaction() } label: {
		                    Label("Add Transaction", systemImage: "plus.circle")
		                }

		                Button { showingAddTransfer = true } label: {
		                    Label("Add Transfer", systemImage: "arrow.left.arrow.right.circle")
		                }

                        Button {
                            selectedAccountForImport = nil
                            showingAccountPicker = true
                        } label: {
                            Label("Import Statement", systemImage: "square.and.arrow.down")
                        }

	                    Button { showingTransfersInbox = true } label: {
	                        Label("Transfer Inbox", systemImage: "tray.full")
	                    }

	                Divider()

	                Button { showingFilter = true } label: {
	                    Label(filter.isActive ? "Filter (Active)" : "Filter", systemImage: "line.3.horizontal.decrease.circle")
	                }

	                if filter.isActive {
	                    Button(role: .destructive) {
	                        filter = TransactionFilter()
	                        // No reload needed - @Query updates automatically
	                    } label: {
	                        Label("Clear Filter", systemImage: "xmark.circle")
	                    }
	                }

	                Divider()

	                Button { enterBulkEdit() } label: {
	                    Label(isBulkEditing ? "Bulk Edit (Active)" : "Bulk Edit", systemImage: "checkmark.circle")
	                }

	                Divider()

	                Button { showingAutoRules = true } label: {
	                    Label("Auto Rules", systemImage: "wand.and.stars")
	                }

	                Divider()

	                Toggle(isOn: $showTransactionTags) {
	                    Label("Show Tags", systemImage: "tag")
	                }
	            } label: {
	                Image(systemName: "ellipsis.circle")
	                    .imageScale(.large)
	            }
	        }
	    }

    @ViewBuilder
    private func transactionSheet(_ transaction: Transaction) -> some View {
        TransactionFormView(transaction: transaction)
    }

	    private var addTransferSheet: some View {
	        TransferFormView()
	    }

        private var transfersInboxSheet: some View {
            TransfersInboxView()
        }

	    private var filterSheet: some View {
	        TransactionFilterView(filter: $filter)
	    }

	    private var bulkEditSheet: some View {
	        BulkEditTransactionsView(transactionIDs: Array(selectedTransactionIDs))
	    }

	    private var autoRulesSheet: some View {
	        AutoRulesView()
	    }

	    private var transferMatchSheet: some View {
	        NavigationStack {
	            if let baseID = transferBaseTransactionID,
	               let base = modelContext.model(for: baseID) as? Transaction {
	                TransferMatchPickerView(
	                    base: base,
	                    currencyCode: currencyCode,
	                    onLinked: { _ in
	                        showingTransferMatch = false
	                        // No reload needed - @Query updates automatically
	                    },
	                    onMarkedUnmatched: {
	                        showingTransferMatch = false
	                        // No reload needed - @Query updates automatically
	                    },
	                    onConvertedToStandard: {
	                        handleConvertedBackToStandard(base)
	                        showingTransferMatch = false
	                        // No reload needed - @Query updates automatically
	                    }
	                )
	            } else {
	                ContentUnavailableView(
	                    "Transfer",
	                    systemImage: "arrow.left.arrow.right",
	                    description: Text("That transaction is no longer available.")
	                )
	                .toolbar {
	                    ToolbarItem(placement: .cancellationAction) {
	                        Button("Done") { showingTransferMatch = false }
	                    }
	                }
	            }
	        }
	        .onDisappear { transferBaseTransactionID = nil }
	    }

        // MARK: - Sheets


		    private var accountPickerSheet: some View {
		        NavigationStack {
		            List(accounts) { account in
	                Button {
	                    selectedAccountForImport = account
	                    showingAccountPicker = false
	                } label: {
	                    HStack {
	                        VStack(alignment: .leading) {
	                            Text(account.name)
	                                .font(.headline)
	                            Text(account.type.rawValue)
	                                .font(.caption)
	                                .foregroundColor(.secondary)
	                        }
	                        Spacer()
	                        Text(account.balance, format: .currency(code: currencyCode))
	                            .foregroundColor(.secondary)
	                    }
	                }
	                .foregroundColor(.primary)
	            }
	            .navigationTitle("Select Account")
	            .toolbar {
	                ToolbarItem(placement: .cancellationAction) {
	                    Button("Cancel") {
                            selectedAccountForImport = nil
                            showingAccountPicker = false
                        }
	                }
		            }
		        }
		        .presentationDetents([.medium])
		        .solidPresentationBackground()
		    }

	    private var uncategorizedSheet: some View {
	        UncategorizedTransactionsSheetContent(
	            currencyCode: currencyCode,
	            categoryGroups: categoryGroups,
	            onDismiss: { navigator.showingUncategorizedTransactions = false }
	        )
	    }

	    private var importSheet: some View {
	        Group {
	            if let account = navigator.selectedAccountForImport {
	                ImportView(account: account)
	            }
	        }
	    }

	    private func handleAccountPickerChange(oldValue: Bool, newValue: Bool) {
	        if oldValue == true && newValue == false && selectedAccountForImport != nil {
	            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
	                if let account = selectedAccountForImport {
	                    navigator.importTransactions(for: account)
                        selectedAccountForImport = nil
	                }
	            }
	        }
	    }

	    private var mainContent: some View {
	        ScrollViewReader { proxy in
	            contentList(proxy: proxy)
	        }
	    }

	    @ViewBuilder
	    private func contentList(proxy: ScrollViewProxy) -> some View {
	        if allTransactions.isEmpty {
	            emptyStateList
	        } else {
	            transactionsList(proxy: proxy)
	        }
	    }

		    private var loadingStateList: some View {
		        List {
		            HStack {
		                Spacer()
		                ProgressView()
		                Spacer()
		            }
		            .listRowSeparator(.hidden)
		            .listRowBackground(Color.clear)
		        }
		        .listStyle(.plain)
		        .scrollContentBackground(.hidden)
		        .background(Color(.systemBackground))
                .background(ScrollOffsetEmitter(id: "AllTransactionsView.scroll"))
	            .coordinateSpace(name: "AllTransactionsView.scroll")
		    }

		    private var emptyStateList: some View {
		        List {
		            EmptyDataCard(
		                systemImage: "list.bullet.rectangle",
		                title: "No Transactions",
		                message: "Add a transaction or import data to get started.",
	                actionTitle: "Add Transaction"
	            ) {
	                navigator.addTransaction()
	            }
	            .listRowInsets(EdgeInsets())
	            .listRowSeparator(.hidden)
	            .listRowBackground(Color.clear)
		        }
		        .listStyle(.plain)
		        .scrollContentBackground(.hidden)
		        .background(Color(.systemBackground))
                .background(ScrollOffsetEmitter(id: "AllTransactionsView.scroll"))
	            .coordinateSpace(name: "AllTransactionsView.scroll")
		    }

		    private func transactionsList(proxy: ScrollViewProxy) -> some View {
		        List {
		            if !filteredTransactions.isEmpty, uncategorizedCount > 0 {
		                Button {
		                    navigator.showUncategorized()
	                } label: {
	                    UncategorizedBanner(countText: bannerText)
	                }
	                .buttonStyle(.plain)
	                .listRowSeparator(.hidden)
	                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 12))
	                .listRowBackground(Color.clear)
	            }

	            if filteredTransactions.isEmpty {
	                ContentUnavailableView(
	                    "No Results",
	                    systemImage: "magnifyingglass",
	                    description: Text("Try adjusting your search or filters.")
	                )
	                .listRowInsets(EdgeInsets())
	                .listRowSeparator(.hidden)
	                .listRowBackground(Color.clear)
	            } else {
	                ForEach(monthSections) { section in
	                    Section(
	                        header: Text(section.title)
	                            .font(.headline)
	                            .textCase(nil)
	                            .padding(.vertical, 8)
	                            .id(section.id)
	                    ) {
		                        ForEach(section.transactions) { transaction in
		                            TransactionRowContent(
		                                transaction: transaction,
		                                currencyCode: currencyCode,
		                                categoryGroups: categoryGroups,
		                                onCategoryChanged: handleCategoryChange,
		                                onTransferSelected: { tx in
		                                    handleTransferSelection(tx)
		                                },
		                                    onIgnoreSelected: { tx in
		                                        handleIgnoreSelection(tx)
		                                    },
		                                onCreateNewCategory: { tx in
		                                    beginNewCategoryCreation(for: tx)
		                                },
		                                isBulkEditing: isBulkEditing,
		                                isSelected: selectedTransactionIDs.contains(transaction.persistentModelID),
		                                showTags: showTransactionTags
		                            )
		                            .contentShape(Rectangle())
		                            .onTapGesture {
		                                if isBulkEditing {
		                                    toggleSelection(transaction)
		                                } else {
		                                    selectedTransaction = transaction
		                                }
		                            }
		                            .onLongPressGesture(minimumDuration: 0.35) {
		                                guard !isBulkEditing else { return }
		                                Haptics.impact(.medium)
		                                selectedTransaction = transaction
		                            }
		                            .contextMenu {
		                                Button {
		                                    selectedTransaction = transaction
		                                } label: {
		                                    Label("Edit Transaction", systemImage: "pencil")
		                                }

		                                if transaction.receipt != nil {
		                                    Button {
		                                        viewingReceipt = transaction.receipt
		                                    } label: {
		                                        Label("View Receipt", systemImage: "doc.text.image")
		                                    }
		                                }

		                                Divider()

		                                Button(role: .destructive) {
		                                    deleteTransactions([transaction])
		                                } label: {
		                                    Label("Delete", systemImage: "trash")
		                                }
		                            }
		                        }
		                        .onDelete { offsets in
		                            guard !isBulkEditing else { return }
		                            deleteTransactions(in: section.transactions, offsets: offsets)
		                        }
	                    }
	                }
	            }

		        }
                .background(ScrollOffsetEmitter(id: "AllTransactionsView.scroll"))
	            .coordinateSpace(name: "AllTransactionsView.scroll")
		        .listSectionSpacing(.custom(14))
		        .simultaneousGesture(
		            DragGesture()
	                .onChanged { _ in handleMonthIndexDragBegan() }
	                .onEnded { _ in handleMonthIndexDragEnded() }
	        , including: .gesture)
	        .overlay(alignment: .trailing) {
	            let indexSections = Array(monthSections.prefix(12))
	            if indexSections.count > 1 && showMonthIndexOverlay {
	                MonthIndexBar(
	                    sections: indexSections,
	                    onSelect: { id in
	                        withAnimation {
	                            proxy.scrollTo(id, anchor: .top)
	                        }
	                    },
	                    onInteractionBegan: handleMonthIndexDragBegan,
	                    onInteractionEnded: handleMonthIndexDragEnded
	                )
	                .padding(.trailing, 4)
	            }
	        }
	    }

    private var newCategorySheet: some View {
        NewBudgetCategorySheet(initialGroup: newCategoryInitialGroup) { category in
            if let id = categoryCreationTransactionID,
               let transaction = allTransactions.first(where: { $0.persistentModelID == id }) {
                handleCategoryChange(for: transaction, newCategory: category)
            }
            resetNewCategoryForm()
        }
    }

    private var bulkEditBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button("Done") {
                    exitBulkEdit()
                }
                .buttonStyle(.bordered)

                Button("Select All") {
                    selectAllShown()
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Button("Clear") {
                    selectedTransactionIDs.removeAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedTransactionIDs.isEmpty)

                Spacer()

                Button("Edit (\(selectedTransactionIDs.count))") {
                    showingBulkEditSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTransactionIDs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func enterBulkEdit() {
        isBulkEditing = true
        selectedTransactionIDs.removeAll()
    }

    private func exitBulkEdit() {
        isBulkEditing = false
        selectedTransactionIDs.removeAll()
    }

    private func toggleSelection(_ transaction: Transaction) {
        if transaction.isTransfer, let transferID = transaction.transferID {
            let legs = fetchTransferLegs(transferID: transferID)
            let ids = legs.map(\.persistentModelID)
            let allSelected = ids.allSatisfy { selectedTransactionIDs.contains($0) }
            if allSelected {
                for id in ids { selectedTransactionIDs.remove(id) }
            } else {
                for id in ids { selectedTransactionIDs.insert(id) }
            }
        } else {
            let id = transaction.persistentModelID
            if selectedTransactionIDs.contains(id) {
                selectedTransactionIDs.remove(id)
            } else {
                selectedTransactionIDs.insert(id)
            }
        }
    }

    private func selectAllShown() {
        for transaction in filteredTransactions {
            if transaction.isTransfer, let transferID = transaction.transferID {
                let legs = fetchTransferLegs(transferID: transferID)
                for leg in legs {
                    selectedTransactionIDs.insert(leg.persistentModelID)
                }
            } else {
                selectedTransactionIDs.insert(transaction.persistentModelID)
            }
        }
    }
    
    private func deleteTransactions(offsets: IndexSet) {
        let targets = offsets.map { filteredTransactions[$0] }
        deleteTransactions(targets)
    }
    
    private func deleteTransactions(in sectionTransactions: [Transaction], offsets: IndexSet) {
        let targets = offsets.map { sectionTransactions[$0] }
        deleteTransactions(targets)
    }
    
    private func deleteTransactions(_ targets: [Transaction]) {
        guard !targets.isEmpty else { return }
        withAnimation {
            var processedTransferIDs: Set<UUID> = []

            for transaction in targets {
                if transaction.isTransfer, let transferID = transaction.transferID {
                    guard !processedTransferIDs.contains(transferID) else { continue }
                    processedTransferIDs.insert(transferID)

                    let legs = fetchTransferLegs(transferID: transferID)
                    for leg in legs {
                        if let account = leg.account {
                            account.balance -= leg.amount
                        }
                    }

                    do {
                        try undoRedoManager.execute(
                            DeleteTransferCommand(modelContext: modelContext, transferID: transferID)
                        )
                        // @Query automatically updates when data changes - no manual removal needed
                    } catch {
                        logger.error("Delete transfer failed: \(error, privacy: .private)")
                        errorCenter.show(title: "Couldn't Delete", message: "Failed to delete that transfer. Please try again.")
                        for leg in legs {
                            modelContext.delete(leg)
                        }
                        // @Query automatically updates when data changes - no manual removal needed
                    }
                } else {
                    let wasUncategorized = transaction.kind == .standard && transaction.category == nil
                    if let account = transaction.account {
                        account.balance -= transaction.amount
                    }

                    do {
                        try undoRedoManager.execute(
                            DeleteTransactionCommand(modelContext: modelContext, transaction: transaction)
                        )
                        // @Query automatically updates when data changes - no manual removal needed
                    } catch {
                        logger.error("Delete transaction failed: \(error, privacy: .private)")
                        errorCenter.show(title: "Couldn't Delete", message: "Failed to delete that transaction. Please try again.")
                        modelContext.delete(transaction)
                        // @Query automatically updates when data changes - no manual removal needed
                    }

                    if wasUncategorized {
                        uncategorizedCount = max(0, uncategorizedCount - 1)
                    }
                }
            }
        }
    }
    
    private func handleMonthIndexDragBegan() {
        guard monthSections.count > 1 else { return }
        monthIndexHideWorkItem?.cancel()
        if !showMonthIndexOverlay {
            withAnimation {
                showMonthIndexOverlay = true
            }
        }
    }
    
    private func handleMonthIndexDragEnded() {
        guard monthSections.count > 1 else { return }
        monthIndexHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation {
                showMonthIndexOverlay = false
            }
        }
        monthIndexHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
    
    private func handleCategoryChange(for transaction: Transaction, newCategory: Category?) {
        let oldKind = transaction.kind
        let oldCategory = transaction.category
        let wasUncategorized = oldKind == .standard && oldCategory == nil
        let oldSnapshot = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: oldSnapshot)

        if oldKind == .ignored {
            transaction.kind = .standard
        }

        let previousName = oldCategory?.name ?? "Uncategorized"
        let newName = newCategory?.name ?? "Uncategorized"
        transaction.category = newCategory
        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

        let isNowUncategorized = transaction.kind == .standard && transaction.category == nil
        if wasUncategorized && !isNowUncategorized {
            uncategorizedCount = max(0, uncategorizedCount - 1)
        } else if !wasUncategorized && isNowUncategorized {
            uncategorizedCount += 1
        }

        if previousName != newName {
            let detail = "Category changed from \(previousName) to \(newName)."
            logHistory(for: transaction, detail: detail)

            if transaction.kind == .standard, transaction.category != nil {
                AutoRulesService(modelContext: modelContext).learnFromCategorization(transaction: transaction, wasAutoDetected: false)
            }

            _ = modelContext.safeSave(context: "AllTransactionsView.handleCategoryChange", showErrorToUser: false)
        }
    }
    
    private func logHistory(for transaction: Transaction, detail: String) {
        guard let modelContext = transaction.modelContext else { return }
        TransactionHistoryService.append(detail: detail, to: transaction, in: modelContext)
    }

    private func handleTransferSelection(_ transaction: Transaction) {
        // Convert standard transaction to transfer
        if transaction.kind == .standard {
            let wasUncategorized = transaction.category == nil
            let old = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

            transaction.kind = .transfer
            transaction.category = nil
            transaction.transferID = nil
            transaction.transferInboxDismissed = false
            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

            // Update uncategorized count if needed
            if wasUncategorized {
                uncategorizedCount = max(0, uncategorizedCount - 1)
            }

            logHistory(for: transaction, detail: "Converted from Standard to Transfer.")

            // Save the changes
            _ = modelContext.safeSave(context: "AllTransactionsView.handleTransferSelection")
        }

        // Open the Edit Transaction sheet which will show Transfer Information section
        selectedTransaction = transaction
    }

    private func handleIgnoreSelection(_ transaction: Transaction) {
        let wasUncategorized = transaction.kind == .standard && transaction.category == nil

        transaction.kind = .ignored
        transaction.category = nil
        transaction.transferID = nil
        transaction.transferInboxDismissed = false

        if wasUncategorized {
            uncategorizedCount = max(0, uncategorizedCount - 1)
        }

        logHistory(for: transaction, detail: "Marked as Ignored.")
    }

    private func handleConvertedBackToStandard(_ transaction: Transaction) {
        // Update uncategorized count - converting back to standard with no category means it's uncategorized
        if transaction.kind == .standard && transaction.category == nil {
            uncategorizedCount += 1
        }

        Task { await refreshUncategorizedCount() }
    }

    private func beginNewCategoryCreation(for transaction: Transaction) {
        categoryCreationTransactionID = transaction.persistentModelID
        newCategoryInitialGroup =
            transaction.category?.group ??
            categoryGroups.first(where: { $0.type != .transfer }) ??
            categoryGroups.first
        showingNewCategorySheet = true
    }

    private func resetNewCategoryForm() {
        showingNewCategorySheet = false
        categoryCreationTransactionID = nil
        newCategoryInitialGroup = nil
    }


    private func fetchTransferLegs(transferID: UUID) -> [Transaction] {
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @MainActor
    private func refreshUncategorizedCount() async {
        do {
            let kind = TransactionKind.standard.rawValue
            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.kindRawValue == kind && $0.category == nil }
            )
            uncategorizedCount = try modelContext.fetchCount(descriptor)
        } catch {
            logger.error("Uncategorized count fetch failed: \(error, privacy: .private)")
            uncategorizedCount = 0
        }
    }

}


extension AllTransactionsView {
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private static let monthShortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

struct TransactionFilterView: View {
    @Binding var filter: TransactionFilter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
    @Query(sort: \TransactionTag.order) private var tags: [TransactionTag]
	    
    @State private var showingSuggestions = false
    @State private var recentPayees: [String] = []

    private var selectedCategoryCount: Int {
        filter.selectedCategoryIDs.count +
        (filter.includeUncategorized ? 1 : 0) +
        (filter.includeIgnored ? 1 : 0)
    }

    private var categorySummaryText: String {
        guard selectedCategoryCount > 0 else { return "All" }
        if selectedCategoryCount == 1 {
            if filter.includeIgnored { return "Ignored" }
            if filter.includeUncategorized { return "Uncategorized" }
            if let selectedID = filter.selectedCategoryIDs.first {
                for group in categoryGroups {
                    if let category = group.sortedCategories.first(where: { $0.persistentModelID == selectedID }) {
                        return category.name
                    }
                }
            }
        }
        return "\(selectedCategoryCount) selected"
    }
    
    private var matchingPayees: [String] {
        if filter.payeeName.isEmpty { return [] }
        return recentPayees.filter { $0.localizedCaseInsensitiveContains(filter.payeeName) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Toggle("Filter by Date", isOn: $filter.useDateRange)
                    if filter.useDateRange {
                        DatePicker("Start Date", selection: $filter.startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $filter.endDate, displayedComponents: .date)
                    }
                }
                
                Section("Payee") {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Payee Name", text: $filter.payeeName)
                            .onChange(of: filter.payeeName) { _, newValue in
                                showingSuggestions = !newValue.isEmpty
                            }
                        
                        if showingSuggestions && !matchingPayees.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            ForEach(matchingPayees.prefix(5), id: \.self) { payee in
                                Button(action: {
                                    filter.payeeName = payee
                                    showingSuggestions = false
                                }) {
                                    Text(payee)
                                        .foregroundColor(.primary)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                
                                if payee != matchingPayees.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                
                Section("Amount Range") {
                    HStack {
                        TextField("Min", text: $filter.minAmount)
                            .keyboardType(.decimalPad)
                        Text("-")
                        TextField("Max", text: $filter.maxAmount)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Filters") {
                    Picker("Account", selection: $filter.account) {
                        Text("All Accounts").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }

                    NavigationLink {
                        CategoryFilterPickerView(
                            selectedCategoryIDs: $filter.selectedCategoryIDs,
                            includeUncategorized: $filter.includeUncategorized,
                            includeIgnored: $filter.includeIgnored,
                            categoryGroups: categoryGroups.filter { $0.type != .transfer }
                        )
                    } label: {
                        LabeledContent("Categories") {
                            Text(categorySummaryText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        TagFilterPickerView(selectedTags: $filter.tags, allTags: tags)
                    } label: {
                        LabeledContent("Tags") {
                            if filter.tags.isEmpty {
                                Text("All")
                                    .foregroundStyle(.secondary)
                            } else if filter.tags.count == 1 {
                                Text(filter.tags[0].name)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(filter.tags.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        filter = TransactionFilter() // Reset
                        dismiss()
                    } label: {
                        Text("Clear Filters")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Filter Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await loadRecentPayees()
        }
    }

	    @MainActor
	    private func loadRecentPayees() async {
	        do {
	            recentPayees = try TransactionQueryService.fetchRecentPayees(modelContext: modelContext)
	        } catch {
	            recentPayees = []
	        }
	    }
}

private struct CategoryFilterPickerView: View {
    @Binding var selectedCategoryIDs: Set<PersistentIdentifier>
    @Binding var includeUncategorized: Bool
    @Binding var includeIgnored: Bool
    let categoryGroups: [CategoryGroup]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    includeUncategorized.toggle()
                } label: {
                    HStack {
                        Text("Uncategorized")
                            .foregroundStyle(.primary)
                        Spacer()
                        if includeUncategorized {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    includeIgnored.toggle()
                } label: {
                    HStack {
                        Text("Ignored")
                            .foregroundStyle(.primary)
                        Spacer()
                        if includeIgnored {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(categoryGroups.enumerated()), id: \.element.persistentModelID) { index, group in
                Section(group.name) {
                    ForEach(group.sortedCategories) { category in
                        Button {
                            toggleCategory(category.persistentModelID)
                        } label: {
                            HStack {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedCategoryIDs.contains(category.persistentModelID) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if index != categoryGroups.indices.last {
                    Divider()
                        .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Clear") { clear() }
            }
        }
    }

    private func toggleCategory(_ id: PersistentIdentifier) {
        if selectedCategoryIDs.contains(id) {
            selectedCategoryIDs.remove(id)
        } else {
            selectedCategoryIDs.insert(id)
        }
    }

    private func clear() {
        selectedCategoryIDs.removeAll()
        includeUncategorized = false
        includeIgnored = false
    }
}

private struct UncategorizedTransactionsSheetContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    let currencyCode: String
    let categoryGroups: [CategoryGroup]
    let onDismiss: () -> Void

    @State private var isLoading = true
    @State private var transactions: [Transaction] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.warning(for: appColorMode))
                    Text("Unable to load transactions")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Done") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                UncategorizedTransactionsView(
                    transactions: transactions,
                    currencyCode: currencyCode,
                    categoryGroups: categoryGroups,
                    onDismiss: onDismiss
                )
            }
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard isLoading else { return }
        do {
            let kind = TransactionKind.standard.rawValue
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.kindRawValue == kind && $0.category == nil },
                sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
            )
            descriptor.fetchLimit = 10_000
            transactions = try modelContext.fetch(descriptor)
            isLoading = false
        } catch {
            errorMessage = "Please try again."
            isLoading = false
        }
    }
}

	private struct TransactionRowContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    let transaction: Transaction
	    let currencyCode: String
	    let categoryGroups: [CategoryGroup]
	    let onCategoryChanged: (Transaction, Category?) -> Void
	    let onTransferSelected: (Transaction) -> Void
        let onIgnoreSelected: (Transaction) -> Void
	    let onCreateNewCategory: (Transaction) -> Void
	    let isBulkEditing: Bool
	    let isSelected: Bool
	    let showTags: Bool
    
    private var showsSplitIcon: Bool {
        let hasChildren = !(transaction.subtransactions ?? []).isEmpty
        return hasChildren || transaction.parentTransaction != nil
    }
    
	    var body: some View {
	        HStack {
            if isBulkEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppColors.tint(for: appColorMode) : .secondary)
                    .font(.title3)
            }
            AccountIcon(account: transaction.account)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.headline)

                    if showsSplitIcon {
                        Text("⇔")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                    }

                    if transaction.receipt != nil {
                        Image(systemName: "doc.text.image.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                HStack {
                    Text(transaction.account?.name ?? "No Account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if transaction.isTransfer {
                        transferBadge
                    } else if transaction.isAdjustment {
                        adjustmentBadge
                    } else {
                        if isBulkEditing {
                            categoryLabel
                        } else {
                            categoryMenu
                        }
                    }
                }

                if showTags, let tags = transaction.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }).prefix(3)) { tag in
                            TransactionTagChip(tag: tag)
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
	            VStack(alignment: .trailing) {
	                Text(transaction.amount, format: .currency(code: currencyCode))
	                    .foregroundColor((transaction.isTransfer || transaction.isAdjustment) ? .primary : (transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary))
	                Text(transaction.date, format: .dateTime.month().day())
	                    .font(.caption)
	                    .foregroundColor(.secondary)
	            }
	        }
	    }

	    private var primaryTitle: String {
	        return transaction.payee
	    }

    private var transferCounterpartyName: String? {
        guard let transferID = transaction.transferID else { return nil }
        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        let other = matches.first { $0.persistentModelID != transaction.persistentModelID }
        return other?.account?.name
    }
    
	    private var categoryMenu: some View {
	        Menu {
	            Button("Transfer") {
	                onTransferSelected(transaction)
	            }
                Button("Ignore Transaction") {
                    onIgnoreSelected(transaction)
                }
	            Button("Uncategorized") {
	                onCategoryChanged(transaction, nil)
	            }
	            ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
	                Section(header: Text(group.name)) {
	                    if let categories = group.categories {
	                        ForEach(categories) { category in
	                            Button(category.name) {
	                                onCategoryChanged(transaction, category)
	                            }
	                        }
	                    }
	                }
	            }
                Divider()
                Button {
                    onCreateNewCategory(transaction)
                } label: {
                    Label("Create New Category", systemImage: "plus.circle")
                }
	            } label: {
	                if transaction.isIgnored {
	                    Text("Ignored")
	                        .font(.caption)
	                        .foregroundColor(AppColors.warning(for: appColorMode))
	                        .padding(.horizontal, 8)
	                        .padding(.vertical, 2)
	                        .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.12)))
	                } else if let category = transaction.category {
		                Text(category.name)
		                    .font(.caption)
	                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            } else {
                Text("Uncategorized")
                    .font(.caption)
                    .foregroundColor(AppColors.warning(for: appColorMode))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.1)))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
    }

    private var categoryLabel: some View {
	        Group {
	            if transaction.isIgnored {
	                Text("Ignored")
	                    .font(.caption)
	                    .foregroundColor(AppColors.warning(for: appColorMode))
	                    .lineLimit(1)
	                    .padding(.horizontal, 8)
	                    .padding(.vertical, 2)
	                    .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.12)))
	                    .fixedSize()
	            } else if let category = transaction.category {
	                Text(category.name)
	                    .font(.caption)
	                    .foregroundColor(.secondary)
	                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    .fixedSize()
            } else {
                Text("Uncategorized")
                    .font(.caption)
                    .foregroundColor(AppColors.warning(for: appColorMode))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.warning(for: appColorMode).opacity(0.1)))
                    .fixedSize()
            }
        }
    }

    private var transferBadge: some View {
        Text("Transfer")
            .font(.caption)
            .foregroundColor(AppColors.tint(for: appColorMode))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppColors.tint(for: appColorMode).opacity(0.1)))
    }

    private var adjustmentBadge: some View {
        Text("Adjustment")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}


private struct AccountIcon: View {
    let account: Account?

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
            Image(systemName: iconName)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private var color: Color {
        account?.type.color ?? .gray
    }

    private var iconName: String {
        account?.type.icon ?? "creditcard"
    }
}

private struct TagFilterPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @Binding var selectedTags: [TransactionTag]
    let allTags: [TransactionTag]
    @State private var searchText: String = ""

    var body: some View {
        List {
            if filteredTags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text(searchText.isEmpty ? "Create a tag from a transaction to use tag filters." : "No tags match your search.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTags) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: tag.colorHex) ?? AppColors.tint(for: appColorMode))
                                .frame(width: 14, height: 14)

                            Text(tag.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isSelected(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Filter Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .cancellationAction) {
                if !selectedTags.isEmpty {
                    Button("Clear") { selectedTags.removeAll() }
                }
            }
        }
    }

    private var filteredTags: [TransactionTag] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func isSelected(_ tag: TransactionTag) -> Bool {
        selectedTags.contains { $0.persistentModelID == tag.persistentModelID }
    }

    private func toggle(_ tag: TransactionTag) {
        if isSelected(tag) {
            selectedTags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            selectedTags.append(tag)
        }
    }
}

private struct UncategorizedBanner: View {
    let countText: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.warning(for: appColorMode).opacity(0.16))
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warning(for: appColorMode))
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Needs Categorizing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.warning(for: appColorMode).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.warning(for: appColorMode).opacity(0.25), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MonthSection: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let transactions: [Transaction]
}

private struct MonthIndexBar: View {
    let sections: [MonthSection]
    let onSelect: (String) -> Void
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 4) {
                ForEach(sections) { section in
                    Text(section.shortTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                        .onTapGesture {
                            onSelect(section.id)
                        }
                }
            }
            .padding(6)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onInteractionBegan?()
                        let ratio = min(max(value.location.y / geo.size.height, 0), 0.999)
                        let index = Int(ratio * CGFloat(sections.count))
                        if sections.indices.contains(index) {
                            onSelect(sections[index].id)
                        }
                    }
                    .onEnded { _ in
                        onInteractionEnded?()
                    }
            )
        }
        .frame(width: 60, height: CGFloat(sections.count) * 26 + 16)
    }
}

#Preview {
    AllTransactionsView(searchText: .constant(""), filter: .constant(TransactionFilter()))
        .modelContainer(for: [Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
