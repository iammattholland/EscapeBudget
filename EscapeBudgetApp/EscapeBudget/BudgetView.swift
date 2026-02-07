import SwiftUI
import SwiftData

struct BudgetView: View {

    @Environment(\.appSettings) private var appSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

	    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
	    @Query(
	        filter: #Predicate<Transaction> { tx in
	            tx.kindRawValue == "Standard"
	        },
	        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
	    ) private var allStandardTransactions: [Transaction]
	    @Query(sort: \MonthlyCategoryBudget.monthStart, order: .reverse) private var monthlyCategoryBudgets: [MonthlyCategoryBudget]

        
    @State private var selectedDate = Date()
    @Binding var searchText: String
    @State private var isMonthHeaderCompact = false
    private let topChrome: AnyView?

    init(searchText: Binding<String>, topChrome: AnyView? = nil) {
        self._searchText = searchText
        self.topChrome = topChrome
    }
    
    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var newGroupType: CategoryGroupType = .expense
    @State private var showingBudgetActions = false
    @State private var showingArchivedCategories = false
    @State private var editMode: EditMode = .inactive
    @State private var showingGroupSelection = false
    @State private var showingAddCategory = false
    @State private var selectedGroupForNewCategory: CategoryGroup?
    @State private var newCategoryName = ""
    @State private var newCategoryBudget = ""
    @State private var selectedCategoryIDForEdit: SelectedCategoryID?
    @State private var movingCategory: Category?
    @State private var collapsedGroups: Set<ObjectIdentifier> = []
    @State private var showingBudgetSetupWizard = false
    @State private var showingApplyBudgetPlan = false

    @State private var isBulkSelecting = false
    @State private var selectedCategoryIDs: Set<PersistentIdentifier> = []
	    @State private var bulkSelectionType: CategoryGroupType?
	    @State private var showingBulkMoveSheet = false
	    @State private var showingSelectionTypeMismatchAlert = false
	    @State private var showingBulkDeleteConfirm = false
	    @State private var cachedMonthTransactions: [Transaction] = []
	    @State private var cachedTransactionsByCategory: [PersistentIdentifier: [Transaction]] = [:]
	    @State private var cachedExpenseBudgetSummariesByID: [PersistentIdentifier: CategoryMonthBudgetSummary] = [:]
	    @State private var budgetCalculator = CategoryBudgetCalculator(transactions: [])
	    @State private var budgetCalculatorBuildKey: (txCount: Int, budgetsCount: Int, token: Int) = (0, 0, 0)

    enum GroupSortOption: String, CaseIterable {
        case custom
        case nameAZ
        case nameZA
        case addedOldest
        case addedNewest

        var title: String {
            switch self {
            case .custom: return "Custom (Reorder)"
            case .nameAZ: return "Name (A–Z)"
            case .nameZA: return "Name (Z–A)"
            case .addedOldest: return "Added (Oldest First)"
            case .addedNewest: return "Added (Newest First)"
            }
        }
    }

    struct SelectedCategoryID: Identifiable {
        let id: PersistentIdentifier
    }

    @State private var groupSortOption: GroupSortOption = .custom

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearch.isEmpty
    }

    private func matchesSearch(_ category: Category) -> Bool {
        let needle = normalizedSearch
        guard !needle.isEmpty else { return true }
        if category.name.localizedCaseInsensitiveContains(needle) { return true }
        if let memo = category.memo, memo.localizedCaseInsensitiveContains(needle) { return true }
        return false
    }

    private func matchesSearch(_ group: CategoryGroup) -> Bool {
        let needle = normalizedSearch
        guard !needle.isEmpty else { return true }
        if group.name.localizedCaseInsensitiveContains(needle) { return true }
        return (group.categories ?? []).contains(where: matchesSearch(_:))
    }

	    private func filteredCategories(in group: CategoryGroup) -> [Category] {
	        let cats = group.sortedCategories.filter { category in
                category.isActive(inMonthStart: selectedMonthStart) ||
                selectedMonthOverrideCategoryIDs.contains(category.persistentModelID)
            }
	        guard isSearching else { return cats }
	        return cats.filter(matchesSearch(_:))
	    }

    private var hasAnySearchResults: Bool {
        guard isSearching else { return true }
        return categoryGroups.contains(where: matchesSearch(_:))
    }

    private var archivedCategoryCount: Int {
        categoryGroups
            .flatMap { $0.categories ?? [] }
            .filter { $0.archivedAfterMonthStart != nil }
            .count
    }

    private var monthChromeCornerRadius: CGFloat {
        isMonthHeaderCompact ? 18 : 22
    }

	    // MARK: - Computed Data (Replaces N+1 Query Pattern)

	    private var selectedMonthStart: Date {
	        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
	    }

	    private var selectedMonthEndExclusive: Date {
	        Calendar.current.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? selectedDate
	    }

    private var archiveCutoffMonthStart: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: selectedMonthStart) ?? selectedMonthStart
    }

	    private var expenseBudgetSummariesByID: [PersistentIdentifier: CategoryMonthBudgetSummary] {
	        cachedExpenseBudgetSummariesByID
	    }

        private var selectedMonthOverrideCategoryIDs: Set<PersistentIdentifier> {
            let month = selectedMonthStart
            return Set(
                monthlyCategoryBudgets.compactMap { budget in
                    let budgetMonth = Calendar.current.date(
                        from: Calendar.current.dateComponents([.year, .month], from: budget.monthStart)
                    ) ?? budget.monthStart
                    guard budgetMonth == month else { return nil }
                    return budget.category?.persistentModelID
                }
            )
        }

        private var selectedMonthOverrideAmountByCategoryID: [PersistentIdentifier: Decimal] {
            let month = selectedMonthStart
            var amounts: [PersistentIdentifier: Decimal] = [:]
            for budget in monthlyCategoryBudgets {
                let budgetMonth = Calendar.current.date(
                    from: Calendar.current.dateComponents([.year, .month], from: budget.monthStart)
                ) ?? budget.monthStart
                guard budgetMonth == month else { continue }
                guard let categoryID = budget.category?.persistentModelID else { continue }
                amounts[categoryID] = budget.amount
            }
            return amounts
        }

		    private struct BudgetViewCacheTaskID: Equatable {
		        var transactionsCount: Int
		        var dataChangeToken: Int
		        var monthStart: Date
		        var groupsCount: Int
		    }

		    private var cacheTaskID: BudgetViewCacheTaskID {
		        BudgetViewCacheTaskID(
		            transactionsCount: allStandardTransactions.count,
		            dataChangeToken: DataChangeTracker.token,
		            monthStart: selectedMonthStart,
		            groupsCount: categoryGroups.count
		        )
		    }

		    @MainActor
		    private func recomputeBudgetCaches() {
		        let start = selectedMonthStart
		        let end = selectedMonthEndExclusive

		        let buildKey = (txCount: allStandardTransactions.count, budgetsCount: monthlyCategoryBudgets.count, token: DataChangeTracker.token)
		        if budgetCalculatorBuildKey != buildKey {
		            budgetCalculator = CategoryBudgetCalculator(
		                transactions: allStandardTransactions,
		                monthlyBudgets: monthlyCategoryBudgets
		            )
		            budgetCalculatorBuildKey = buildKey
		        }

		        let monthTx = allStandardTransactions.filter { tx in
		            tx.date >= start &&
		            tx.date < end &&
		            tx.account?.isTrackingOnly != true
		        }
		        cachedMonthTransactions = monthTx

		        var grouped: [PersistentIdentifier: [Transaction]] = [:]
		        grouped.reserveCapacity(categoryGroups.flatMap { $0.categories ?? [] }.count)
		        for transaction in monthTx {
		            if let categoryID = transaction.category?.persistentModelID {
		                grouped[categoryID, default: []].append(transaction)
		            }
		        }
		        cachedTransactionsByCategory = grouped

		        let categories = categoryGroups
		            .filter { $0.type == .expense }
		            .flatMap { $0.categories ?? [] }

		        var summaries: [PersistentIdentifier: CategoryMonthBudgetSummary] = [:]
		        summaries.reserveCapacity(categories.count)
		        for category in categories {
		            summaries[category.persistentModelID] = budgetCalculator.monthSummary(for: category, monthStart: start)
		        }
		        cachedExpenseBudgetSummariesByID = summaries
		    }

		    /// Transactions for the selected month (cached)
		    private var monthTransactions: [Transaction] {
		        cachedMonthTransactions
	    }

    /// Transactions grouped by category ID for efficient lookup (computed once per render)
    /// Replaces the N+1 anti-pattern where each row filtered all transactions
	    private var transactionsByCategory: [PersistentIdentifier: [Transaction]] {
	        cachedTransactionsByCategory
	    }

    private var monthChromeView: some View {
        MonthNavigationHeader(selectedDate: $selectedDate, isCompact: isMonthHeaderCompact)
            .padding(.horizontal, AppDesign.Theme.Spacing.tight)
            .padding(.vertical, isMonthHeaderCompact ? AppDesign.Theme.Spacing.compact : AppDesign.Theme.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: monthChromeCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: monthChromeCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, AppDesign.Theme.Spacing.medium)
            .padding(.top, AppDesign.Theme.Spacing.micro)
            .padding(.bottom, AppDesign.Theme.Spacing.xSmall)
    }
    
    var body: some View {
        budgetListView
    }

    private var baseList: some View {
        List {
            if topChrome != nil {
                AppChromeListRow(topChrome: topChrome, scrollID: "BudgetView.scroll")
            }
            monthChromeView
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            budgetListContent
        }
    }

    private var styledList: some View {
        baseList
            .listStyle(.insetGrouped)
            .appListCompactSpacing()
            .appListTopInset()
            .environment(\.editMode, $editMode)
    }

	    private var scrollTrackingList: some View {
	        styledList
	            .coordinateSpace(name: "BudgetView.scroll")
	            .background(ScrollOffsetEmitter(id: "BudgetView.scroll", emitLegacy: true))
	            .task(id: cacheTaskID) {
	                recomputeBudgetCaches()
	                postBudgetAlertsIfNeeded(for: selectedDate, monthTransactions: monthTransactions, startOfMonth: selectedMonthStart)
	            }
	            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
	                let shouldCompact = offset < -AppDesign.Theme.Layout.scrollCompactThreshold
	                if shouldCompact != isMonthHeaderCompact {
	                    withAnimation(.easeInOut(duration: 0.15)) {
	                        isMonthHeaderCompact = shouldCompact
                    }
                }
            }
    }

    @ToolbarContentBuilder
    private var budgetToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingBudgetActions = true
            } label: {
                Image(systemName: "ellipsis").appEllipsisIcon()
            }
        }
    }

    private var budgetListWithToolbar: some View {
        scrollTrackingList
            .toolbar { budgetToolbar }
    }

    private var budgetListWithDialogs: some View {
        budgetListWithToolbar
            .confirmationDialog("Select Group for Category", isPresented: $showingGroupSelection) {
                ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                    Button(group.name) {
                        selectedGroupForNewCategory = group
                        showingAddCategory = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingAddGroup) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Group Name", text: $newGroupName)
                        }

                        Section("Type") {
                            Picker("Group Type", selection: $newGroupType) {
                                Text("Expense").tag(CategoryGroupType.expense)
                                Text("Income").tag(CategoryGroupType.income)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .navigationTitle("New Category Group")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                newGroupName = ""
                                newGroupType = .expense
                                showingAddGroup = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addGroup()
                            }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingBudgetActions) {
                NavigationStack {
                    BudgetActionsSheet(
                        canUndo: undoRedoManager.canUndo,
                        canRedo: undoRedoManager.canRedo,
                        isBulkSelecting: isBulkSelecting,
                        isReordering: editMode == .active,
                        hasGroups: !categoryGroups.isEmpty,
                        currentSort: groupSortOption,
                        onUndo: { do { try undoRedoManager.undo() } catch { } },
                        onRedo: { do { try undoRedoManager.redo() } catch { } },
                        onSetUpBudget: { showingBudgetSetupWizard = true },
                        onApplyBudgetPlan: {
                            showingBudgetActions = false
                            showingApplyBudgetPlan = true
                        },
                        onSort: { applyGroupSort($0) },
                        onExpandAll: { withAnimation { collapsedGroups.removeAll() } },
                        onCollapseAll: { withAnimation { collapsedGroups = Set(categoryGroups.map { ObjectIdentifier($0) }) } },
                        onToggleBulkSelect: {
                            withAnimation {
                                if isBulkSelecting {
                                    isBulkSelecting = false
                                    selectedCategoryIDs.removeAll()
                                    bulkSelectionType = nil
                                } else {
                                    editMode = .inactive
                                    isBulkSelecting = true
                                    selectedCategoryIDs.removeAll()
                                    bulkSelectionType = nil
                                }
                            }
                        },
                        onToggleReorder: {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        },
                        archivedCategoryCount: archivedCategoryCount,
                        onManageArchived: { showingArchivedCategories = true },
                        onAddGroup: { showingAddGroup = true },
                        onAddCategory: { showingGroupSelection = true }
                    )
                    .navigationTitle("Budget Actions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingBudgetActions = false }
                        }
                    }
                }
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("Category Name", text: $newCategoryName)
                TextField(
                    (selectedGroupForNewCategory?.type ?? .expense) == .income ? "Forecast Amount" : "Budget Amount",
                    text: $newCategoryBudget
                )
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                    newCategoryBudget = ""
                }
                Button("Add") {
                    if let group = selectedGroupForNewCategory {
                        let budgetAmount = Decimal(string: newCategoryBudget) ?? 0
                        addCategory(to: group, name: newCategoryName, budget: budgetAmount)
                        newCategoryName = ""
                        newCategoryBudget = ""
                    }
                }
            }
            .alert("Selection", isPresented: $showingSelectionTypeMismatchAlert) {
                Button("OK") { }
            } message: {
                Text("You can only bulk select income or expense categories at a time.")
            }
            .confirmationDialog(
                "Delete selected categories?",
                isPresented: $showingBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelectedCategories()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove the selected categories.")
            }
    }

    private var budgetListWithSheets: some View {
        budgetListWithDialogs
            .sheet(item: $selectedCategoryIDForEdit, onDismiss: {
                selectedCategoryIDForEdit = nil
            }) { selectedID in
                if let category = categoryForEdit(id: selectedID.id) {
	                    CategoryEditSheet(category: category, monthStart: selectedMonthStart) {
	                        selectedCategoryIDForEdit = nil
	                    }
	                } else {
	                    NavigationStack {
	                        ProgressView("Loading category…")
                            .appSecondaryBodyText()
                            .padding(AppDesign.Theme.Spacing.large)
                            .navigationTitle("Edit Category")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .sheet(item: $movingCategory) { category in
                MoveCategorySheet(category: category)
            }
            .sheet(isPresented: $showingBulkMoveSheet) {
                if let selectionType = bulkSelectionType {
                    BulkMoveCategoriesSheet(
                        categoryIDs: Array(selectedCategoryIDs),
                        requiredType: selectionType
                    ) {
                        selectedCategoryIDs.removeAll()
                        bulkSelectionType = nil
                    }
                }
            }
            .sheet(isPresented: $showingBudgetSetupWizard) {
                BudgetSetupWizardView(replaceExistingDefault: true)
            }
            .sheet(isPresented: $showingArchivedCategories) {
                NavigationStack {
                    ArchivedCategoriesSheet(restoreMonthStart: selectedMonthStart)
                        .navigationTitle("Archived Categories")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingArchivedCategories = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingApplyBudgetPlan) {
                NavigationStack {
                    ApplyBudgetPlanSheet(
                        initialSourceMonthStart: selectedMonthStart,
                        categoryGroups: categoryGroups,
                        selectedCategoryIDs: selectedCategoryIDs,
                        monthlyCategoryBudgets: monthlyCategoryBudgets,
                        allStandardTransactions: allStandardTransactions
                    )
                }
            }
    }

    private var budgetListWithChrome: some View {
        budgetListWithSheets
            .safeAreaInset(edge: .bottom) {
                if isBulkSelecting {
                    bulkSelectionBar
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 45)
                    .onEnded { value in
                        let calendar = Calendar.current

                        // Only trigger if horizontal swipe is dominant (more horizontal than vertical)
                        let horizontalDistance = abs(value.translation.width)
                        let verticalDistance = abs(value.translation.height)

                        guard horizontalDistance > verticalDistance else {
                            return
                        }

                        // Swipe left (next month)
                        if value.translation.width < -AppDesign.Theme.Layout.swipeActionThreshold {
                            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = nextMonth
                                }
                            }
                        }
                        // Swipe right (previous month)
                        else if value.translation.width > AppDesign.Theme.Layout.swipeActionThreshold {
                            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = previousMonth
                                }
                            }
                        }
                    }
            , including: .gesture)
    }

    private var budgetListView: some View {
        budgetListWithChrome
    }

	    private func postBudgetAlertsIfNeeded(for month: Date, monthTransactions: [Transaction], startOfMonth: Date) {
	        guard appSettings.budgetAlerts else { return }

	        let calendar = Calendar.current

        let expenseCategories = categoryGroups
            .filter { $0.type == .expense }
            .flatMap { $0.categories ?? [] }

        guard !expenseCategories.isEmpty else { return }

        struct BudgetStatus {
            let category: Category
            let spent: Decimal
            let remaining: Decimal
            let ratioUsed: Double
        }

	        var statuses: [BudgetStatus] = []
	        statuses.reserveCapacity(expenseCategories.count)

	        for category in expenseCategories {
	            guard let summary = expenseBudgetSummariesByID[category.persistentModelID] else { continue }
	            let spent = summary.spent
	            guard spent > 0 else { continue }

	            let remaining = summary.endingAvailable
	            let limitDouble = NSDecimalNumber(decimal: max(Decimal.zero, summary.effectiveLimitThisMonth)).doubleValue
	            let ratio = limitDouble > 0 ? NSDecimalNumber(decimal: spent).doubleValue / limitDouble : 0

	            statuses.append(
	                BudgetStatus(category: category, spent: spent, remaining: remaining, ratioUsed: ratio)
	            )
	        }

        guard !statuses.isEmpty else { return }

        let monthKey: String = {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: startOfMonth)
        }()

        let overspent = statuses.filter { $0.remaining < 0 }
        if let worst = overspent.min(by: { $0.remaining < $1.remaining }) {
            let overAmount = -worst.remaining
            let message: String
            if overspent.count == 1 {
                message = "You’re overspent in \(worst.category.name) by \(formatCurrency(overAmount)) for \(month.formatted(.dateTime.month(.wide)))."
            } else {
                message = "\(overspent.count) categories are overspent for \(month.formatted(.dateTime.month(.wide))). Worst: \(worst.category.name) (\(formatCurrency(overAmount)) over)."
            }

            InAppNotificationService.post(
                title: "Overspending Alert",
                message: message,
                type: .alert,
                in: modelContext,
                topic: .budgetAlerts,
                dedupeKey: "budget.overspent.\(monthKey)"
            )
            return
        }

        let nearLimit = statuses.filter { $0.ratioUsed >= 0.8 }
        if let worst = nearLimit.max(by: { $0.ratioUsed < $1.ratioUsed }) {
            let percent = Int((worst.ratioUsed * 100).rounded())
            let message: String
            if nearLimit.count == 1 {
                message = "You’ve used \(percent)% of \(worst.category.name) for \(month.formatted(.dateTime.month(.wide)))."
            } else {
                message = "You’re nearing your budget in \(nearLimit.count) categories for \(month.formatted(.dateTime.month(.wide))). Top: \(worst.category.name) (\(percent)% used)."
            }

            InAppNotificationService.post(
                title: "Budget Alert",
                message: message,
                type: .warning,
                in: modelContext,
                topic: .budgetAlerts,
                dedupeKey: "budget.near.\(monthKey)"
            )
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appSettings.currencyCode
        return formatter.string(from: amount as NSDecimalNumber) ?? amount.description
    }

    private func applyGroupSort(_ option: GroupSortOption) {
        groupSortOption = option

        if option == .custom {
            withAnimation {
                isBulkSelecting = false
                selectedCategoryIDs.removeAll()
                bulkSelectionType = nil
                editMode = .active
            }
            return
        }

        withAnimation {
            editMode = .inactive
        }

        let incomeGroups = categoryGroups.filter { $0.type == .income }
        let expenseGroups = categoryGroups.filter { $0.type == .expense }
        let transferGroups = categoryGroups.filter { $0.type == .transfer }

        let sortedExpenses: [CategoryGroup] = {
            switch option {
            case .custom:
                return expenseGroups
            case .nameAZ:
                return expenseGroups.sorted {
                    let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return $0.order < $1.order
                }
            case .nameZA:
                return expenseGroups.sorted {
                    let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
                    if cmp != .orderedSame { return cmp == .orderedDescending }
                    return $0.order > $1.order
                }
            case .addedOldest:
                return expenseGroups.sorted { $0.order < $1.order }
            case .addedNewest:
                return expenseGroups.sorted { $0.order > $1.order }
            }
        }()

        let newGroupOrder = incomeGroups + sortedExpenses + transferGroups

        let oldOrders = Dictionary(uniqueKeysWithValues: categoryGroups.map { ($0.persistentModelID, $0.order) })
        let newOrders = Dictionary(uniqueKeysWithValues: newGroupOrder.enumerated().map { ($0.element.persistentModelID, $0.offset) })

        do {
            try undoRedoManager.execute(
                ReorderCategoryGroupsCommand(
                    modelContext: modelContext,
                    oldOrders: oldOrders,
                    newOrders: newOrders
                )
            )
        } catch {
            for (id, order) in newOrders {
                (modelContext.model(for: id) as? CategoryGroup)?.order = order
            }
            modelContext.safeSave(context: "BudgetView.applyGroupSort.fallback")
        }
    }

    private var expenseGroupsForList: [CategoryGroup] {
        categoryGroups.filter { $0.type == .expense && matchesSearch($0) }
    }

    private var incomeGroupsForList: [CategoryGroup] {
        categoryGroups.filter { $0.type == .income && matchesSearch($0) }
    }

    @ViewBuilder
    private var budgetListContent: some View {
        if isSearching, !hasAnySearchResults {
            ContentUnavailableView.search(text: searchText)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            ForEach(incomeGroupsForList) { group in
                incomeGroupSection(group)
            }

            ForEach(expenseGroupsForList) { group in
                expenseGroupSection(group)
            }
            .onMove(perform: moveGroups)
        }
    }

    @ViewBuilder
    private func incomeGroupSection(_ incomeGroup: CategoryGroup) -> some View {
        Section(
            header: GroupHeaderView(
                group: incomeGroup,
                isCollapsed: isSearching ? false : isGroupCollapsed(incomeGroup),
                onToggleCollapse: { toggleGroupCollapse(incomeGroup) },
                showsSelectionActions: isBulkSelecting,
                selectionCount: selectionCount(in: incomeGroup),
                totalCount: selectableCategories(in: incomeGroup).count,
                selectionEnabled: selectionControlsEnabled(for: incomeGroup),
                onSelectAll: { selectAll(in: incomeGroup) },
                onClear: { clearSelection(in: incomeGroup) }
            )
            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
        ) {
            if isSearching || !isGroupCollapsed(incomeGroup) {
                ForEach(filteredCategories(in: incomeGroup)) { category in
                    categoryRow(for: category)
                }

                Button {
                    selectedGroupForNewCategory = incomeGroup
                    showingAddCategory = true
                } label: {
                    Label("Add Income Source", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                        .font(AppDesign.Theme.Typography.secondaryBody)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .padding(.vertical, AppDesign.Theme.Spacing.compact)
            }
        }
    }

    @ViewBuilder
    private func expenseGroupSection(_ group: CategoryGroup) -> some View {
        Section(
            header: GroupHeaderView(
                group: group,
                isCollapsed: isSearching ? false : isGroupCollapsed(group),
                onToggleCollapse: { toggleGroupCollapse(group) },
                showsSelectionActions: isBulkSelecting,
                selectionCount: selectionCount(in: group),
                totalCount: selectableCategories(in: group).count,
                selectionEnabled: selectionControlsEnabled(for: group),
                onSelectAll: { selectAll(in: group) },
                onClear: { clearSelection(in: group) }
            )
        ) {
            if isSearching || !isGroupCollapsed(group) {
                ForEach(filteredCategories(in: group)) { category in
                    categoryRow(for: category)
                }
                .onMove { source, destination in
                    moveCategories(in: group, from: source, to: destination)
                }

                Button {
                    selectedGroupForNewCategory = group
                    showingAddCategory = true
                } label: {
                    Label("Add Budget Category", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                        .font(AppDesign.Theme.Typography.secondaryBody)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .padding(.vertical, AppDesign.Theme.Spacing.compact)
            }
        }
    }

	    private func categoryRow(for category: Category) -> some View {
	        let isSelected = selectedCategoryIDs.contains(category.persistentModelID)
	        // Pass only transactions for THIS category (pre-grouped) - no filtering needed
	        let categoryTransactions = transactionsByCategory[category.persistentModelID] ?? []
	        let summary = category.group?.type == .expense ? expenseBudgetSummariesByID[category.persistentModelID] : nil
	        let row = BudgetCategoryRowView(
	            category: category,
	            selectedDate: selectedDate,
	            transactions: categoryTransactions,
                monthlyOverrideAmount: selectedMonthOverrideAmountByCategoryID[category.persistentModelID],
	            budgetSummary: summary,
	            showsSelection: isBulkSelecting,
	            isSelected: isSelected
	        ) {
	            if isBulkSelecting {
	                toggleSelection(for: category)
            } else {
                selectedCategoryIDForEdit = SelectedCategoryID(id: category.persistentModelID)
            }
        }

        if isBulkSelecting {
            return AnyView(row)
        }

        return AnyView(
            row
                .swipeActions(edge: HorizontalEdge.leading, allowsFullSwipe: false) {
                    Button {
                        movingCategory = category
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(AppDesign.Colors.tint(for: appColorMode))
                }
                .swipeActions(edge: HorizontalEdge.trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        selectedCategoryIDForEdit = SelectedCategoryID(id: category.persistentModelID)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(AppDesign.Colors.tint(for: appColorMode))
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    Haptics.impact(.medium)
                    selectedCategoryIDForEdit = SelectedCategoryID(id: category.persistentModelID)
                }
        )
    }

    private func categoryForEdit(id: PersistentIdentifier) -> Category? {
        for group in categoryGroups {
            if let match = group.categories?.first(where: { $0.persistentModelID == id }) {
                return match
            }
        }
        return nil
    }

    private var bulkSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppDesign.Theme.Spacing.tight) {
                Button("Done") {
                    withAnimation {
                        isBulkSelecting = false
                        selectedCategoryIDs.removeAll()
                        bulkSelectionType = nil
                    }
                }
                .appActionBarSecondary()

                Button(selectedCategoryIDs.isEmpty ? "Select All" : "Clear All") {
                    withAnimation {
                        if selectedCategoryIDs.isEmpty {
                            selectAllVisibleCategories()
                        } else {
                            selectedCategoryIDs.removeAll()
                            bulkSelectionType = nil
                        }
                    }
                }
                .appActionBarSecondary()

                Spacer()

                Button("Move (\(selectedCategoryIDs.count))") {
                    showingBulkMoveSheet = true
                }
                .appActionBarPrimary()
                .disabled(selectedCategoryIDs.isEmpty || bulkSelectionType == nil)

                Button("Delete") {
                    showingBulkDeleteConfirm = true
                }
                .appActionBarSecondary()
                .disabled(selectedCategoryIDs.isEmpty)
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.medium)
            .padding(.vertical, AppDesign.Theme.Spacing.tight)
            .background(.thinMaterial)
        }
    }

    private func selectableCategories(in group: CategoryGroup) -> [Category] {
        filteredCategories(in: group)
    }

    private func selectionCount(in group: CategoryGroup) -> Int {
        selectableCategories(in: group)
            .reduce(0) { count, category in
                count + (selectedCategoryIDs.contains(category.persistentModelID) ? 1 : 0)
            }
    }

    private func selectionControlsEnabled(for group: CategoryGroup) -> Bool {
        let groupType = group.type
        return bulkSelectionType == nil || bulkSelectionType == groupType
    }

    private func selectAll(in group: CategoryGroup) {
        let categories = selectableCategories(in: group)
        guard let first = categories.first else { return }

        let type = first.group?.type ?? .expense
        if let bulkSelectionType, bulkSelectionType != type {
            showingSelectionTypeMismatchAlert = true
            return
        }

        bulkSelectionType = type
        for category in categories {
            selectedCategoryIDs.insert(category.persistentModelID)
        }
    }

    private func clearSelection(in group: CategoryGroup) {
        let categories = selectableCategories(in: group)
        for category in categories {
            selectedCategoryIDs.remove(category.persistentModelID)
        }
        if selectedCategoryIDs.isEmpty {
            bulkSelectionType = nil
        }
    }

    private func deleteSelectedCategories() {
        let idsToDelete = selectedCategoryIDs
        guard !idsToDelete.isEmpty else { return }

        withAnimation {
            let categories = idsToDelete.compactMap { modelContext.model(for: $0) as? Category }
            for category in categories {
                let categoryID = category.persistentModelID
                var descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { tx in
                        tx.category?.persistentModelID == categoryID
                    }
                )
                descriptor.fetchLimit = 1
                let hasAnyTransactions = !(((try? modelContext.fetch(descriptor)) ?? []).isEmpty)

                if hasAnyTransactions {
                    do {
                        try undoRedoManager.execute(
                            UpdateCategoryCommand(
                                modelContext: modelContext,
                                category: category,
                                newName: category.name,
                                newAssigned: category.assigned,
                                newActivity: category.activity,
                                newOrder: category.order,
                                newIcon: category.icon,
                                newMemo: category.memo,
                                newGroup: category.group,
                                newArchivedAfterMonthStart: archiveCutoffMonthStart
                            )
                        )
                    } catch {
                        category.archivedAfterMonthStart = archiveCutoffMonthStart
                        modelContext.safeSave(context: "BudgetView.bulkArchiveCategory.fallback")
                    }
                    continue
                }

                do {
                    try undoRedoManager.execute(
                        DeleteCategoryCommand(modelContext: modelContext, category: category)
                    )
                } catch {
                    modelContext.delete(category)
                    modelContext.safeSave(context: "BudgetView.bulkDeleteCategory.fallback")
                }
            }
        }

        selectedCategoryIDs.removeAll()
        bulkSelectionType = nil
        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: selectedMonthStart,
            saveContext: "BudgetView.deleteSelectedCategories.syncSavingsGoals"
        )
    }

    private func toggleSelection(for category: Category) {
        let id = category.persistentModelID
        if selectedCategoryIDs.contains(id) {
            selectedCategoryIDs.remove(id)
            if selectedCategoryIDs.isEmpty {
                bulkSelectionType = nil
            }
            return
        }

        let type = category.group?.type ?? .expense
        if let bulkSelectionType, bulkSelectionType != type {
            showingSelectionTypeMismatchAlert = true
            return
        }

        bulkSelectionType = type
        selectedCategoryIDs.insert(id)
    }

    private func selectAllVisibleCategories() {
        selectedCategoryIDs.removeAll()

        var categoriesToSelect: [Category] = []

        for incomeGroup in incomeGroupsForList {
            guard isSearching || !isGroupCollapsed(incomeGroup) else { continue }
            categoriesToSelect.append(contentsOf: filteredCategories(in: incomeGroup))
        }

        for group in expenseGroupsForList {
            guard isSearching || !isGroupCollapsed(group) else { continue }
            categoriesToSelect.append(contentsOf: filteredCategories(in: group))
        }

        // If the list is empty, keep selection empty.
        guard let first = categoriesToSelect.first else { return }

        let type = first.group?.type ?? .expense
        bulkSelectionType = type
        for category in categoriesToSelect where (category.group?.type ?? .expense) == type {
            selectedCategoryIDs.insert(category.persistentModelID)
        }
    }

    // MARK: - Group Actions
    
    private func addGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let maxOrder = categoryGroups.map { $0.order }.max() ?? -1

        withAnimation {
            do {
                try undoRedoManager.execute(
                    AddCategoryGroupCommand(
                        modelContext: modelContext,
                        name: trimmed,
                        order: maxOrder + 1,
                        type: newGroupType
                    )
                )
            } catch {
                // Fallback
                let newGroup = CategoryGroup(name: trimmed, order: maxOrder + 1, type: newGroupType)
                modelContext.insert(newGroup)
                modelContext.safeSave(context: "BudgetView.addGroup.fallback")
            }
            newGroupName = ""
            newGroupType = .expense
            showingAddGroup = false
        }
    }
    
    private func moveGroups(from source: IndexSet, to destination: Int) {
        let oldOrders = Dictionary(uniqueKeysWithValues: categoryGroups.map { ($0.persistentModelID, $0.order) })
        var groups = categoryGroups
        groups.move(fromOffsets: source, toOffset: destination)
        let newOrders = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($0.element.persistentModelID, $0.offset) })

        withAnimation {
            do {
                try undoRedoManager.execute(
                    ReorderCategoryGroupsCommand(modelContext: modelContext, oldOrders: oldOrders, newOrders: newOrders)
                )
            } catch {
                for (id, order) in newOrders {
                    (modelContext.model(for: id) as? CategoryGroup)?.order = order
                }
                modelContext.safeSave(context: "BudgetView.moveGroups.fallback")
            }
        }
    }
    
    // MARK: - Category Actions
    
    private func addCategory(to group: CategoryGroup, name: String = "", budget: Decimal = 0) {
        let maxOrder = (group.categories?.map { $0.order }.max() ?? -1)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Category" : trimmed
        do {
            try undoRedoManager.execute(
                AddCategoryCommand(
                    modelContext: modelContext,
                    name: finalName,
                    assigned: budget,
                    activity: 0,
                    order: maxOrder + 1,
                    createdAt: selectedMonthStart,
                    group: group
                )
            )
        } catch {
            let newCategory = Category(
                name: finalName,
                assigned: budget,
                activity: 0,
                order: maxOrder + 1
            )
            newCategory.createdAt = selectedMonthStart
            newCategory.group = group
            modelContext.insert(newCategory)
            modelContext.safeSave(context: "BudgetView.addCategory.fallback")
        }
    }
    
    private func deleteCategory(_ category: Category) {
        withAnimation {
            let categoryID = category.persistentModelID
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.category?.persistentModelID == categoryID
                }
            )
            descriptor.fetchLimit = 1
            let hasAnyTransactions = !(((try? modelContext.fetch(descriptor)) ?? []).isEmpty)

            if hasAnyTransactions {
                do {
                    try undoRedoManager.execute(
                        UpdateCategoryCommand(
                            modelContext: modelContext,
                            category: category,
                            newName: category.name,
                            newAssigned: category.assigned,
                            newActivity: category.activity,
                            newOrder: category.order,
                            newIcon: category.icon,
                            newMemo: category.memo,
                            newGroup: category.group,
                            newArchivedAfterMonthStart: archiveCutoffMonthStart
                        )
                    )
                } catch {
                    category.archivedAfterMonthStart = archiveCutoffMonthStart
                    modelContext.safeSave(context: "BudgetView.archiveCategory.fallback")
                }
                SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                    modelContext: modelContext,
                    referenceDate: selectedMonthStart,
                    saveContext: "BudgetView.deleteCategory.archive.syncSavingsGoals"
                )
                return
            }

            do {
                try undoRedoManager.execute(
                    DeleteCategoryCommand(modelContext: modelContext, category: category)
                )
            } catch {
                modelContext.delete(category)
                modelContext.safeSave(context: "BudgetView.deleteCategory.fallback")
            }
            SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                modelContext: modelContext,
                referenceDate: selectedMonthStart,
                saveContext: "BudgetView.deleteCategory.delete.syncSavingsGoals"
            )
        }
    }
    
    private func moveCategories(in group: CategoryGroup, from source: IndexSet, to destination: Int) {
        let oldOrders = Dictionary(uniqueKeysWithValues: group.sortedCategories.map { ($0.persistentModelID, $0.order) })
        var categories = group.sortedCategories
        categories.move(fromOffsets: source, toOffset: destination)
        let newOrders = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($0.element.persistentModelID, $0.offset) })

        withAnimation {
            do {
                try undoRedoManager.execute(
                    ReorderCategoriesCommand(modelContext: modelContext, oldOrders: oldOrders, newOrders: newOrders)
                )
            } catch {
                for (id, order) in newOrders {
                    (modelContext.model(for: id) as? Category)?.order = order
                }
                modelContext.safeSave(context: "BudgetView.moveCategories.fallback")
            }
        }
    }

    // MARK: - Collapse Helpers
    
    private func isGroupCollapsed(_ group: CategoryGroup) -> Bool {
        collapsedGroups.contains(ObjectIdentifier(group))
    }
    
    private func toggleGroupCollapse(_ group: CategoryGroup) {
        let id = ObjectIdentifier(group)
        withAnimation {
            if collapsedGroups.contains(id) {
                collapsedGroups.remove(id)
            } else {
                collapsedGroups.insert(id)
            }
        }
    }
}

// MARK: - Group Header View

struct GroupHeaderView: View {

    @Environment(\.appSettings) private var appSettings
    let group: CategoryGroup
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let showsSelectionActions: Bool
    let selectionCount: Int
    let totalCount: Int
    let selectionEnabled: Bool
    let onSelectAll: () -> Void
    let onClear: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var newName = ""
    
    var body: some View {
        let totalAssigned = (group.categories ?? []).reduce(0) { $0 + $1.assigned }
        
        HStack(spacing: AppDesign.Theme.Spacing.compact) {
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .appCaptionText()
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand \(group.name)" : "Collapse \(group.name)")
            
	        HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
	                Text(group.name)
	                    .appSectionTitleText()
	                    .foregroundStyle(.primary)
	                
	                Text(totalAssigned, format: .currency(code: appSettings.currencyCode))
	                    .appSecondaryBodyText()
	                    .foregroundStyle(.secondary)
	        }
            
            Spacer()

            if showsSelectionActions && totalCount > 0 {
                if selectionCount > 0 {
                    Text("\(selectionCount)/\(totalCount)")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                Button(selectionCount == totalCount ? "Clear" : "Select All") {
                    if selectionCount == totalCount {
                        onClear()
                    } else {
                        onSelectAll()
                    }
                }
                .font(AppDesign.Theme.Typography.secondaryBody.weight(.semibold))
                .foregroundStyle(selectionEnabled ? AppDesign.Colors.tint(for: appColorMode) : .secondary)
                .disabled(!selectionEnabled)
            }

            Menu {
                Button {
                    newName = group.name
                    showingRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").appEllipsisIcon()
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
        .alert("Rename Group", isPresented: $showingRenameAlert) {
            TextField("Group Name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                group.name = newName
            }
        }
        .confirmationDialog("Delete Group?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(group)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the group and all its categories.")
        }
    }
}

// MARK: - Budget Category Row View

	struct BudgetCategoryRowView: View {

	    @Environment(\.appSettings) private var appSettings
	    let category: Category
	    let selectedDate: Date
	    let transactions: [Transaction]
        let monthlyOverrideAmount: Decimal?
	    let budgetSummary: CategoryMonthBudgetSummary?
	    let showsSelection: Bool
	    let isSelected: Bool
	    let onTap: () -> Void
	    	    @Environment(\.appColorMode) private var appColorMode
	    
	    private var monthNet: Decimal {
	        transactions.reduce(Decimal.zero) { $0 + $1.amount }
	    }

	    private var configuredBudgetAmount: Decimal {
	        guard category.group?.type == .expense else { return category.assigned }
	        if category.budgetType == .lumpSum {
	            return category.assigned
	        }
            if let monthlyOverrideAmount {
                return monthlyOverrideAmount
            }
	        return budgetSummary?.budgeted ?? category.assigned
	    }

	    private var needsBudgetConfiguration: Bool {
	        guard category.group?.type == .expense else { return false }
	        return configuredBudgetAmount <= 0
	    }
	    
	    init(
	        category: Category,
	        selectedDate: Date,
	        transactions: [Transaction],
            monthlyOverrideAmount: Decimal? = nil,
	        budgetSummary: CategoryMonthBudgetSummary? = nil,
	        showsSelection: Bool = false,
	        isSelected: Bool = false,
	        onTap: @escaping () -> Void
	    ) {
	        self.category = category
	        self.selectedDate = selectedDate
	        self.transactions = transactions
            self.monthlyOverrideAmount = monthlyOverrideAmount
	        self.budgetSummary = budgetSummary
	        self.showsSelection = showsSelection
	        self.isSelected = isSelected
	        self.onTap = onTap
	    }

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
            // Category icon
            Circle()
                .fill(AppDesign.Colors.tint(for: appColorMode).opacity(0.1))
                .frame(width: 40, height: 40)
                    .overlay(
                        Text(category.icon ?? String(category.name.prefix(1)).uppercased())
                            .appDisplayText(
                                category.icon != nil ? AppDesign.Theme.DisplaySize.large : AppDesign.Theme.DisplaySize.small,
                                weight: .semibold
                            )
                            .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                    )
                
	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
	                    Text(category.name)
	                        .font(AppDesign.Theme.Typography.body)
	                        .fontWeight(.medium)
	                        .foregroundStyle(.primary)
	                    
	                    if needsBudgetConfiguration {
	                        Text("No Budget Assigned")
	                            .appCaption2Text()
	                            .fontWeight(.medium)
	                            .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
	                    }
	                }
                
                Spacer()
                
	                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.hairline) {
		                    Text(configuredBudgetAmount, format: .currency(code: appSettings.currencyCode))
		                        .appSecondaryBodyText()
		                        .foregroundStyle(.primary)
		                        .lineLimit(1)
		                        .minimumScaleFactor(0.5)
	                    
	                    if category.group?.type == .income {
	                        if monthNet > 0 {
	                            Text("Received: \(monthNet.formatted(.currency(code: appSettings.currencyCode)))")
	                                .appCaption2Text()
	                                .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
	                        }
	                    } else {
	                        if let summary = budgetSummary {
	                            let remaining = summary.endingAvailable
	                            if category.budgetType == .lumpSum {
	                                Text("\(remaining >= 0 ? "Pool Left" : "Pool Over"): \(abs(remaining).formatted(.currency(code: appSettings.currencyCode)))")
	                                    .appCaption2Text()
	                                    .foregroundStyle(remaining >= 0 ? .secondary : AppDesign.Colors.danger(for: appColorMode))
	                            } else if configuredBudgetAmount > 0 || summary.startingAvailable != 0 {
	                                Text("\(remaining >= 0 ? "Left" : "Over"): \(abs(remaining).formatted(.currency(code: appSettings.currencyCode)))")
	                                    .appCaption2Text()
	                                    .foregroundStyle(remaining >= 0 ? .secondary : AppDesign.Colors.danger(for: appColorMode))
	                            } else if summary.spent > 0 {
	                                Text("Spent: \(summary.spent.formatted(.currency(code: appSettings.currencyCode)))")
	                                    .appCaption2Text()
	                                    .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
	                            }
	                        } else {
	                            let spent = max(Decimal.zero, -monthNet)
	                            let remaining = configuredBudgetAmount - spent
	                            if configuredBudgetAmount > 0 {
	                                Text("\(remaining >= 0 ? "Left" : "Over"): \(abs(remaining).formatted(.currency(code: appSettings.currencyCode)))")
	                                    .appCaption2Text()
	                                    .foregroundStyle(remaining >= 0 ? .secondary : AppDesign.Colors.danger(for: appColorMode))
	                            } else if spent > 0 {
	                                Text("Spent: \(spent.formatted(.currency(code: appSettings.currencyCode)))")
	                                .appCaption2Text()
	                                .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
	                            }
	                        }
	                    }
	                }
                
                if showsSelection {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .appTitleText()
                        .foregroundStyle(isSelected ? AppDesign.Colors.tint(for: appColorMode) : Color.secondary.opacity(0.35))
                } else {
                    Image(systemName: "chevron.right")
                        .appCaptionText()
                        .foregroundStyle(.tertiary)
                }
        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}


// MARK: - Category Transactions Sheet

struct CategoryBudgetLogicSnapshot {
    let periodSummary: CategoryBudgetPeriodSummary
    let monthSummary: CategoryMonthBudgetSummary
    let periodRange: (start: Date, end: Date)
    let monthStart: Date
}

struct CategoryTransactionsSheet: View {

    @Environment(\.appSettings) private var appSettings
    let category: Category
    let transactions: [Transaction]
    let dateRange: (start: Date, end: Date)
    let budgetLogic: CategoryBudgetLogicSnapshot?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    @State private var sortOption: SortOption = .dateNewest
    @State private var selectedTransaction: Transaction?
    @State private var selectedTab: DetailTab = .transactions

    init(
        category: Category,
        transactions: [Transaction],
        dateRange: (start: Date, end: Date),
        budgetLogic: CategoryBudgetLogicSnapshot? = nil
    ) {
        self.category = category
        self.transactions = transactions
        self.dateRange = dateRange
        self.budgetLogic = budgetLogic
    }

    enum DetailTab: String, CaseIterable, Identifiable {
        case transactions = "Transactions"
        case budgetLogic = "Budget Logic"

        var id: String { rawValue }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateNewest = "Date: Newest"
        case dateOldest = "Date: Oldest"
        case amountHigh = "Amount: High to Low"
        case amountLow = "Amount: Low to High"
        case nameAZ = "Name: A to Z"
        
        var id: String { rawValue }
    }
    
    private var sortedTransactions: [Transaction] {
        switch sortOption {
        case .dateNewest:
            return transactions.sorted { $0.date > $1.date }
        case .dateOldest:
            return transactions.sorted { $0.date < $1.date }
        case .amountHigh:
            return transactions.sorted { abs($0.amount) > abs($1.amount) }
        case .amountLow:
            return transactions.sorted { abs($0.amount) < abs($1.amount) }
        case .nameAZ:
            return transactions.sorted { $0.payee < $1.payee }
        }
    }
    
    private var totalSpent: Decimal {
        let net = transactions.reduce(Decimal.zero) { $0 + $1.amount }
        let used = max(Decimal.zero, -net)
        return used
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary header
                VStack(spacing: AppDesign.Theme.Spacing.medium) {
                    HStack(spacing: AppDesign.Theme.Spacing.large) {
                        VStack(spacing: AppDesign.Theme.Spacing.micro) {
                            Text("Budget")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text(category.assigned, format: .currency(code: appSettings.currencyCode))
                                .appTitleText()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack(spacing: AppDesign.Theme.Spacing.micro) {
                            Text("Spent")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text(totalSpent, format: .currency(code: appSettings.currencyCode))
                                .appTitleText()
                                .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack(spacing: AppDesign.Theme.Spacing.micro) {
                            Text("Remaining")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text(category.assigned - totalSpent, format: .currency(code: appSettings.currencyCode))
                                .appTitleText()
                                .foregroundStyle((category.assigned - totalSpent) >= 0 ? AppDesign.Colors.success(for: appColorMode) : AppDesign.Colors.danger(for: appColorMode))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    
                    // Date range
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM d, yyyy"
                    Text("\(formatter.string(from: dateRange.start)) – \(formatter.string(from: dateRange.end))")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGroupedBackground))

                if budgetLogic != nil {
                    Picker("View", selection: $selectedTab) {
                        ForEach(DetailTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                    .padding(.top, AppDesign.Theme.Spacing.tight)
                    .padding(.bottom, AppDesign.Theme.Spacing.micro)
                }

                if selectedTab == .budgetLogic {
                    budgetLogicContent
                } else {
                    if transactions.isEmpty {
                        EmptyDataCard(
                            systemImage: "tray",
                            title: "No transactions",
                            message: "Transactions in this category will appear here"
                        )
                    } else {
                        List {
                            ForEach(sortedTransactions) { transaction in
                                Button {
                                    selectedTransaction = transaction
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                                            Text(transaction.payee)
                                                .font(AppDesign.Theme.Typography.body)
                                                .fontWeight(.medium)

                                            HStack(spacing: AppDesign.Theme.Spacing.compact) {
                                                Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                                                    .appCaptionText()
                                                    .foregroundStyle(.secondary)

                                                if let account = transaction.account {
                                                    Text(account.name)
                                                        .appCaptionText()
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }

                                        Spacer()

	                                        Text(transaction.amount, format: .currency(code: appSettings.currencyCode))
	                                            .appSecondaryBodyText()
	                                            .fontWeight(.semibold)
	                                            .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary)
	                                            .lineLimit(1)
	                                            .minimumScaleFactor(0.5)

                                        Image(systemName: "chevron.right")
                                            .appCaptionText()
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, AppDesign.Theme.Spacing.micro)
                            }
                        }
                        .sheet(item: $selectedTransaction) { transaction in
                            TransactionFormView(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedTab == .transactions {
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var budgetLogicContent: some View {
        if let logic = budgetLogic {
            ScrollView {
                VStack(spacing: AppDesign.Theme.Spacing.tight) {
                    budgetLogicCard(
                        title: "Selected Range",
                        subtitle: "\(logic.periodRange.start.formatted(date: .abbreviated, time: .omitted)) – \(logic.periodRange.end.formatted(date: .abbreviated, time: .omitted))",
                        rows: [
                            ("Starting", logic.periodSummary.startingAvailable),
                            ("Budgeted", logic.periodSummary.budgeted),
                            ("Spent", logic.periodSummary.spent),
                            ("Ending", logic.periodSummary.endingAvailable)
                        ]
                    )

                    budgetLogicCard(
                        title: "Month Snapshot",
                        subtitle: logic.monthStart.formatted(.dateTime.month(.wide).year()),
                        rows: [
                            ("Starting", logic.monthSummary.startingAvailable),
                            ("Budgeted", logic.monthSummary.budgeted),
                            ("Spent", logic.monthSummary.spent),
                            ("Ending", logic.monthSummary.endingAvailable),
                            ("Next Carryover", logic.monthSummary.carryoverToNextMonth)
                        ]
                    )

                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                        Text("Rules")
                            .appSectionTitleText()
                        ruleRow(label: "Type", value: category.budgetType.title)
                        ruleRow(label: "Overspending", value: category.overspendHandling.title)
                        ruleRow(
                            label: "Archived",
                            value: category.archivedAfterMonthStart == nil
                                ? "No"
                                : "After \(category.archivedAfterMonthStart?.formatted(.dateTime.month(.abbreviated).year()) ?? "")"
                        )
                    }
                    .appCardSurface(fill: Color(.systemBackground), stroke: Color.primary.opacity(0.05))
                }
                .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                .padding(.vertical, AppDesign.Theme.Spacing.tight)
            }
        } else {
            EmptyDataCard(
                systemImage: "info.circle",
                title: "No budget logic available",
                message: "Budget logic details are available from Review budget categories."
            )
        }
    }

    private func budgetLogicCard(
        title: String,
        subtitle: String,
        rows: [(String, Decimal)]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
            Text(title)
                .appSectionTitleText()
            Text(subtitle)
                .appCaptionText()
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1.formatted(.currency(code: appSettings.currencyCode)))
                        .appSecondaryBodyText()
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
        .appCardSurface(fill: Color(.systemBackground), stroke: Color.primary.opacity(0.05))
    }

    private func ruleRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .appSecondaryBodyText()
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Category Edit Sheet

		struct CategoryEditSheet: View {

		    @Environment(\.appSettings) private var appSettings
	    let category: Category
	    let monthStart: Date
	    let onDismiss: () -> Void
	    	    
	    @Environment(\.modelContext) private var modelContext
	    @Environment(\.undoRedoManager) private var undoRedoManager
	    @Environment(\.appColorMode) private var appColorMode
	    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
	    @State private var showingDeleteConfirmation = false
	    @State private var showingEmojiPicker = false
	    @State private var showingMoveSheet = false
		    @State private var moveTargetTypeOverride: CategoryGroupType? = nil
		    @State private var budgetSection: CategoryGroupType = .expense
		    @State private var name: String = ""
		    @State private var assigned: Decimal = 0
		    @State private var defaultAssigned: Decimal = 0
		    @State private var memoText: String = ""
		    @State private var icon: String? = nil
		    @State private var budgetType: CategoryBudgetType = .monthlyReset
		    @State private var overspendHandling: CategoryOverspendHandling = .carryNegative
		    @State private var hasMonthlyBudgetOverride = false
		    @State private var hasAnyTransactions = false

		    private var amountLabel: String {
		        if budgetSection == .income {
		            return "Forecast Amount"
		        }
		        if budgetType == .lumpSum {
		            return "Pool Amount"
		        }
		        return "Budget Amount"
		    }

		    private var monthLabel: String {
		        monthStart.formatted(.dateTime.month(.wide).year())
		    }

		    private var destructiveActionTitle: String {
		        hasAnyTransactions ? "Archive Category" : "Delete Category"
		    }

		    private var destructiveDialogTitle: String {
		        if hasAnyTransactions {
		            return "Archive \"\(category.name)\" for \(monthLabel) and later?"
		        }
		        return "Delete \"\(category.name)\"?"
		    }

		    private var destructiveDialogMessage: String {
		        if hasAnyTransactions {
		            return "This category will be hidden for \(monthLabel) and later, but will remain on existing transactions and historical reports."
		        }
		        return "This will permanently delete this category and cannot be undone."
		    }

            private var archiveCutoffMonthStart: Date {
                Calendar.current.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            }

		    private var monthlyBudgetNote: String? {
		        guard (category.group?.type ?? .expense) == .expense else { return nil }
		        guard budgetType != .lumpSum else { return nil }
		        if hasMonthlyBudgetOverride {
		            return "Override for \(monthLabel). Default: \(defaultAssigned.formatted(.currency(code: appSettings.currencyCode)))."
		        }
		        return "Using default: \(defaultAssigned.formatted(.currency(code: appSettings.currencyCode)))."
		    }
		    
		    var body: some View {
		        NavigationStack {
		            Form {
		                Section {
                    VStack(alignment: .leading) {
                        Text("Category Name")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $name)
                            .font(AppDesign.Theme.Typography.body)
                    }
		                    
		                    VStack(alignment: .leading) {
		                        Text(amountLabel)
		                            .appCaptionText()
		                            .foregroundStyle(.secondary)
		                        TextField("Amount", value: $assigned, format: .currency(code: appSettings.currencyCode))
		                            .keyboardType(.decimalPad)
		                    }
		                    if let note = monthlyBudgetNote {
		                        Text(note)
		                            .appCaptionText()
		                            .foregroundStyle(.secondary)
		                    }

		                    if (category.group?.type ?? .expense) == .expense,
		                       budgetType != .lumpSum {
		                        HStack {
		                            Button("Set as default") {
		                                defaultAssigned = assigned
		                                hasMonthlyBudgetOverride = false
		                            }
		                            Spacer()
		                            Button("Copy to next month") {
		                                copyMonthlyBudget(offsetMonths: 1)
		                            }
		                        }
		                        .appSecondaryBodyText()
		                    }
		                    
		                    VStack(alignment: .leading) {
		                        Text("Memo (Optional)")
		                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Add a note...", text: $memoText)
                    }
	                } header: {
	                    Text("Details")
	                }

	                if (category.group?.type ?? .expense) == .expense {
	                    Section {
	                        Picker("Type", selection: $budgetType) {
	                            ForEach(CategoryBudgetType.allCases) { type in
	                                Text(type.title).tag(type)
	                            }
	                        }
	                        Text(budgetType.detail)
	                            .appCaptionText()
	                            .foregroundStyle(.secondary)
	                    } header: {
	                        Text("Type")
	                    }
	                }

	                if (category.group?.type ?? .expense) == .expense,
	                   budgetType != .monthlyReset {
	                    Section {
	                        Picker("Overspending", selection: $overspendHandling) {
	                            ForEach(CategoryOverspendHandling.allCases) { handling in
	                                Text(handling.title).tag(handling)
	                            }
	                        }
	                        Text(overspendHandling.detail)
	                            .appCaptionText()
	                            .foregroundStyle(.secondary)
	                    } header: {
	                        Text("Overspending")
	                    }
	                }

	                Section("Group") {
	                    if (category.group?.type ?? .expense) != .transfer {
	                        Picker("Budget Section", selection: $budgetSection) {
	                            Text("Expense").tag(CategoryGroupType.expense)
	                            Text("Income").tag(CategoryGroupType.income)
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        moveTargetTypeOverride = nil
                        showingMoveSheet = true
                    } label: {
                        HStack {
                            Text("Move Category")
                            Spacer()
                            Text(category.group?.name ?? "None")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Category Icon")
                        Spacer()
                        if let icon {
                            Button(action: { showingEmojiPicker = true }) {
                                Text(icon)
                                    .appTitleText()
                            }
                        } else {
                            Button(action: { showingEmojiPicker = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .appTitleText()
                                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                            }
                        }
                    }
                } header: {
                    Text("Icon")
                }
                
		                Section {
		                    Button(role: .destructive) {
		                        showingDeleteConfirmation = true
		                    } label: {
		                        HStack {
		                            Spacer()
		                            Label(destructiveActionTitle, systemImage: "trash")
		                            Spacer()
		                        }
		                    }
		                }
		            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        onDismiss()
                    }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
#if canImport(UIKit)
                        KeyboardUtilities.dismiss()
#endif
                    }
                }
            }
		            .confirmationDialog(
		                destructiveDialogTitle,
		                isPresented: $showingDeleteConfirmation,
		                titleVisibility: .visible
		            ) {
		                if hasAnyTransactions {
		                    Button("Archive", role: .destructive) {
		                        archiveCategory()
		                        onDismiss()
		                    }
		                } else {
		                    Button("Delete", role: .destructive) {
		                        do {
		                            try undoRedoManager.execute(
		                                DeleteCategoryCommand(modelContext: modelContext, category: category)
		                            )
		                        } catch {
		                            modelContext.delete(category)
		                            modelContext.safeSave(context: "CategoryEditorSheet.deleteCategory.fallback")
		                        }
                                SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                                    modelContext: modelContext,
                                    referenceDate: monthStart,
                                    saveContext: "CategoryEditSheet.deleteCategory.syncSavingsGoals"
                                )
		                        onDismiss()
		                    }
		                }
		                Button("Cancel", role: .cancel) { }
		            } message: {
		                Text(destructiveDialogMessage)
		            }
		        }
		        .onAppear {
		            name = category.name
		            defaultAssigned = category.assigned
		            assigned = category.assigned
		            memoText = category.memo ?? ""
		            icon = category.icon
		            budgetType = category.budgetType
		            overspendHandling = category.overspendHandling
		            loadMonthlyBudgetIfNeeded()
		            recomputeHasAnyTransactions()
		            syncBudgetSectionFromCategory()
		        }
		        .onChange(of: budgetType) { _, _ in
		            loadMonthlyBudgetIfNeeded()
		        }
		        .onChange(of: budgetSection) { _, newValue in
		            handleBudgetSectionChange(newValue)
		        }
        .sheet(isPresented: $showingMoveSheet, onDismiss: {
            moveTargetTypeOverride = nil
            syncBudgetSectionFromCategory()
        }) {
            MoveCategorySheet(category: category, targetTypeOverride: moveTargetTypeOverride)
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerSheet(
                selectedEmoji: Binding(
                    get: { icon },
                    set: { icon = $0 }
                ),
                categoryName: name
            )
        }
    }

    private func syncBudgetSectionFromCategory() {
        let current = category.group?.type ?? .expense
        budgetSection = (current == .income) ? .income : .expense
    }

    private func handleBudgetSectionChange(_ newValue: CategoryGroupType) {
        let current = category.group?.type ?? .expense
        guard current != .transfer else { return }

        if newValue == .income && current != .income {
            moveToIncomeGroup()
            return
        }

        if newValue == .expense && current == .income {
            moveTargetTypeOverride = .expense
            showingMoveSheet = true
        }
    }

    private func moveToIncomeGroup() {
        guard let incomeGroup = categoryGroups.first(where: { $0.type == .income }) else {
            return
        }

        let destinationMaxOrder = (incomeGroup.categories ?? []).map(\.order).max() ?? -1

        do {
            try undoRedoManager.execute(
                UpdateCategoryCommand(
                    modelContext: modelContext,
                    category: category,
                    newName: category.name,
                    newAssigned: category.assigned,
                    newActivity: category.activity,
                    newOrder: destinationMaxOrder + 1,
                    newIcon: category.icon,
                    newMemo: category.memo,
                    newGroup: incomeGroup
                )
            )
        } catch {
            category.group = incomeGroup
            category.order = destinationMaxOrder + 1
            modelContext.safeSave(context: "CategoryEditSheet.moveToIncomeGroup.fallback")
        }
    }

	    private func saveChanges() {
	        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
	        let finalName = trimmedName.isEmpty ? category.name : trimmedName
	        let trimmedMemo = memoText.trimmingCharacters(in: .whitespacesAndNewlines)
	        let finalMemo = trimmedMemo.isEmpty ? nil : trimmedMemo

	        let isIncome = budgetSection == .income || category.group?.type == .income
	        let isExpense = (category.group?.type ?? .expense) == .expense && !isIncome
	        let isPool = isExpense && budgetType == .lumpSum

	        let newAssigned: Decimal = {
	            if isIncome { return assigned }
	            if isPool { return assigned }
	            return defaultAssigned
	        }()

	        do {
	            try undoRedoManager.execute(
	                UpdateCategoryCommand(
	                    modelContext: modelContext,
	                    category: category,
	                    newName: finalName,
	                    newAssigned: newAssigned,
	                    newActivity: category.activity,
	                    newOrder: category.order,
	                    newIcon: icon,
	                    newMemo: finalMemo,
	                    newGroup: category.group,
	                    newBudgetTypeRawValue: budgetType.rawValue,
	                    newOverspendHandlingRawValue: overspendHandling.rawValue
	                )
	            )
	        } catch {
	            category.name = finalName
	            category.assigned = newAssigned
	            category.icon = icon
	            category.memo = finalMemo
	            category.budgetType = budgetType
	            category.overspendHandling = overspendHandling
	            modelContext.safeSave(context: "CategoryEditorSheet.saveChanges.fallback")
	        }

	        if isExpense, !isPool {
	            persistMonthlyBudgetOverrideIfNeeded()
	        }
	    }

	    private func recomputeHasAnyTransactions() {
	        let categoryID = category.persistentModelID
	        var descriptor = FetchDescriptor<Transaction>(
	            predicate: #Predicate<Transaction> { tx in
	                tx.category?.persistentModelID == categoryID
	            }
	        )
	        descriptor.fetchLimit = 1
	        let found = (try? modelContext.fetch(descriptor)) ?? []
	        hasAnyTransactions = !found.isEmpty
	    }

	    private func loadMonthlyBudgetIfNeeded() {
	        guard (category.group?.type ?? .expense) == .expense else { return }
	        guard budgetType != .lumpSum else {
	            assigned = defaultAssigned
	            hasMonthlyBudgetOverride = false
	            return
	        }

	        let categoryID = category.persistentModelID
	        var descriptor = FetchDescriptor<MonthlyCategoryBudget>(
	            predicate: #Predicate<MonthlyCategoryBudget> { entry in
	                entry.category?.persistentModelID == categoryID &&
	                entry.monthStart == monthStart
	            }
	        )
	        descriptor.fetchLimit = 1
	        if let existing = (try? modelContext.fetch(descriptor))?.first {
	            assigned = existing.amount
	            hasMonthlyBudgetOverride = true
	        } else {
	            assigned = defaultAssigned
	            hasMonthlyBudgetOverride = false
	        }
	    }

	    private func persistMonthlyBudgetOverrideIfNeeded() {
	        let categoryID = category.persistentModelID
	        var descriptor = FetchDescriptor<MonthlyCategoryBudget>(
	            predicate: #Predicate<MonthlyCategoryBudget> { entry in
	                entry.category?.persistentModelID == categoryID &&
	                entry.monthStart == monthStart
	            }
	        )
	        descriptor.fetchLimit = 1
	        let existing = (try? modelContext.fetch(descriptor))?.first

	        if assigned == defaultAssigned {
	            if let existing {
	                modelContext.delete(existing)
	                modelContext.safeSave(context: "CategoryEditSheet.deleteMonthlyBudgetOverride")
	            }
	            return
	        }

	        if let existing {
	            existing.amount = assigned
	        } else {
	            let entry = MonthlyCategoryBudget(
	                monthStart: monthStart,
	                amount: assigned,
	                category: category,
	                isDemoData: category.isDemoData
	            )
	            modelContext.insert(entry)
	        }
	        modelContext.safeSave(context: "CategoryEditSheet.saveMonthlyBudgetOverride")
	    }

	    private func copyMonthlyBudget(offsetMonths: Int) {
	        guard (category.group?.type ?? .expense) == .expense else { return }
	        guard budgetType != .lumpSum else { return }
	        guard let target = Calendar.current.date(byAdding: .month, value: offsetMonths, to: monthStart) else { return }
	        let targetMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: target)) ?? target
	        let categoryID = category.persistentModelID

	        var descriptor = FetchDescriptor<MonthlyCategoryBudget>(
	            predicate: #Predicate<MonthlyCategoryBudget> { entry in
	                entry.category?.persistentModelID == categoryID &&
	                entry.monthStart == targetMonth
	            }
	        )
	        descriptor.fetchLimit = 1
	        let existing = (try? modelContext.fetch(descriptor))?.first

	        if assigned == defaultAssigned {
	            if let existing {
	                modelContext.delete(existing)
	            }
	        } else if let existing {
	            existing.amount = assigned
	        } else {
	            modelContext.insert(
	                MonthlyCategoryBudget(
	                    monthStart: targetMonth,
	                    amount: assigned,
	                    category: category,
	                    isDemoData: category.isDemoData
	                )
	            )
	        }
	        modelContext.safeSave(context: "CategoryEditSheet.copyMonthlyBudget")
	    }

	    private func archiveCategory() {
	        do {
	            try undoRedoManager.execute(
	                UpdateCategoryCommand(
	                    modelContext: modelContext,
	                    category: category,
	                    newName: category.name,
	                    newAssigned: category.assigned,
	                    newActivity: category.activity,
	                    newOrder: category.order,
	                    newIcon: category.icon,
	                    newMemo: category.memo,
	                    newGroup: category.group,
	                    newArchivedAfterMonthStart: archiveCutoffMonthStart
	                )
	            )
	        } catch {
	            category.archivedAfterMonthStart = archiveCutoffMonthStart
	            modelContext.safeSave(context: "CategoryEditSheet.archiveCategory.fallback")
	        }
            SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                modelContext: modelContext,
                referenceDate: monthStart,
                saveContext: "CategoryEditSheet.archiveCategory.syncSavingsGoals"
            )
	    }
	}

struct EmojiPickerSheet: View {

    @Environment(\.appSettings) private var appSettings
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    var categoryName: String? = nil

    @State private var customEmojiText: String = ""
    @State private var customEmojiError: String? = nil
    @FocusState private var customEmojiFocused: Bool
    
    private let categories: [(String, [String])] = [
        ("Suggested", []),
        ("Common", ["🏠","🛒","🍔","☕️","🚗","⛽️","🧾","💡","📱","💻","🎉","🎮","🏋️","🧘","💊","🩺","🐶","👶","🎓","💼","💰","🏦","💳","🧰","🧹","🧺","🧯","🛠️","🧱","📦","🎁"]),
        ("Money", ["💵","💰","🏦","💳","🧾","📈","📉","💹","💸","🪙","🧮","🏧","💱"]),
        ("Income", ["💰","💵","🏦","📈","🧾","💼","🧑‍💻","🧑‍🏫","🧑‍⚕️","🏢","🪪","🎁","💸","💹","🏆"]),
        ("Bills & Utilities", ["💡","🔌","💧","🔥","🧾","📡","📶","📺","☎️","🛜","🗑️","♻️","🏠","🔧","🧯"]),
        ("Food & Drink", ["🛒","🍔","🍕","🌮","🥗","🍣","🍜","🥡","🍦","🍩","🍪","🍫","🍎","🥐","🥩","🥓","🥚","🧀","🥑","🍇","🍉","🥤","🧃","☕️","🫖","🍺","🍷","🥂","🍸"]),
        ("Shopping", ["🛍️","🛒","👕","👖","👗","🧥","👟","🥿","👠","👜","🎁","💄","🧴","🧼","🧻","🪥","🧽","🪒","🕶️","📦"]),
        ("Home", ["🏠","🛏️","🛋️","🚪","🪟","🧹","🧺","🧽","🧼","🪣","🧯","🛠️","🔧","🧰","🪚","🪛","🧱","🪜","🌿","🪴"]),
        ("Transport", ["🚗","🚙","🚕","🚌","🚇","🚆","✈️","🚲","🛴","🛵","🚘","🛞","⛽️","🅿️","🧾","🛣️","🚦","🧳"]),
        ("Health", ["💊","🩺","🦷","👓","🧠","🧬","🧫","🩹","🏥","🧴","🧼","🧘","🏃","🏋️","🥼"]),
        ("Family & Kids", ["👶","🍼","🧸","🎒","🧒","👨‍👩‍👧‍👦","🎠","🎡","🧩","🧾"]),
        ("Pets", ["🐶","🐱","🐾","🦴","🦮","🐕","🐈","🏥","💊"]),
        ("Entertainment", ["🎬","🍿","🎟️","🎮","🎧","🎵","🎤","🎸","🎹","🎨","🎭","🎳","🎲","🕹️","📚"]),
        ("Travel", ["✈️","🏨","🧳","🗺️","🏝️","🏖️","🗽","⛺️","🚂","🚢","🛂","🛃","🛅","🧾"]),
        ("Work & Admin", ["💼","🏢","🧑‍💻","📅","📌","📎","🗂️","🗃️","📄","🧾","🪪","🛂","📝","✍️","📬"]),
        ("Education", ["🎓","📚","📖","🧠","🧑‍🏫","🏫","📝","✏️","📐","📏","🧪"]),
        ("Gifts & Charity", ["🎁","💝","❤️","🙏","🤝","🎗️","🌍","🧸","🎉"]),
        ("Symbols", ["✅","❌","⚠️","⭐️","🔥","💯","🔒","🔑","📌","📍","➕","➖","➗","✖️","💲","❤️","🟢","🟡","🔴"])
    ]

    private var suggestedEmojis: [String] {
        let base = [categoryName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }
        return EmojiSuggester.suggest(for: base)
    }

    private var customEmojiCandidate: String? {
        customEmojiText.firstEmojiString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.large) {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                            Text("Custom Choice")
                                .appSectionTitleText()
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

                            styledTextField {
                                TextField("Type or paste an emoji", text: $customEmojiText)
                                    .focused($customEmojiFocused)
                                    .onSubmit {
                                        if let candidate = customEmojiCandidate {
                                            selectedEmoji = candidate
                                            dismiss()
                                        } else {
                                            customEmojiError = "Please enter a single emoji."
                                        }
                                    }
                            }

                            if let candidate = customEmojiCandidate {
                                Button {
                                    selectedEmoji = candidate
                                    dismiss()
                                } label: {
                                    Text("Use \(candidate)")
                                        .font(AppDesign.Theme.Typography.secondaryBody.weight(.semibold))
                                }
                                .appSecondaryCTA(controlSize: .small)
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                                .accessibilityLabel("Use emoji \(candidate)")
                            }

                            if let customEmojiError {
                                Text(customEmojiError)
                                    .appCaptionText()
                                    .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                    .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                            }
                        }
                    }

                    if !suggestedEmojis.isEmpty {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                            Text("Suggested")
                                .appSectionTitleText()
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

                            emojiGrid(suggestedEmojis)
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                                .appCardSurface(padding: AppDesign.Theme.Spacing.medium)
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                        }
                    }

	                    ForEach(filteredCategories, id: \.0) { category in
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                            Text(category.0)
                                .appSectionTitleText()
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                            
                            emojiGrid(category.1)
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                                .appCardSurface(padding: AppDesign.Theme.Spacing.medium)
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                        }
                    }
                    
                    // Option to clear
                    Button(role: .destructive, action: {
                        selectedEmoji = nil
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Label("Remove Icon", systemImage: "trash")
                            Spacer()
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.small)
                    }
                    .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                    .appCardSurface(padding: AppDesign.Theme.Spacing.medium)
                    .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.medium)
            }
            .navigationTitle("Select Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .solidPresentationBackground()
        .onChange(of: customEmojiText) { _, _ in
            customEmojiError = nil
        }
    }

    @ViewBuilder
    private func styledTextField<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, AppDesign.Theme.Spacing.medium)
            .padding(.vertical, AppDesign.Theme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
    }

    @ViewBuilder
    private func emojiGrid(_ emojis: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: AppDesign.Theme.Spacing.small) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    selectedEmoji = emoji
                    dismiss()
                } label: {
                    Text(emoji)
                        .appDisplayText(AppDesign.Theme.DisplaySize.xxxLarge, weight: .regular)
                        .frame(width: 45, height: 45)
                        .background(selectedEmoji == emoji ? AppDesign.Colors.tint(for: appColorMode).opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredCategories: [(String, [String])] {
        categories.filter { $0.0 != "Suggested" }
    }
}

private struct ArchivedCategoriesSheet: View {

    @Environment(\.appSettings) private var appSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \MonthlyCategoryBudget.monthStart) private var monthlyCategoryBudgets: [MonthlyCategoryBudget]
    
    let restoreMonthStart: Date
    @State private var restoringCategoryID: PersistentIdentifier?
    @State private var pendingRestoreCategoryID: PersistentIdentifier?
    @State private var pendingRestoreName: String = ""
    @State private var showingRestoreConfirmation = false

    private var archivedCategories: [Category] {
        categories.filter { $0.archivedAfterMonthStart != nil }
    }

    private var restoreMonthLabel: String {
        restoreMonthStart.formatted(.dateTime.month(.wide).year())
    }

    private var pendingRestoreCategory: Category? {
        guard let pendingRestoreCategoryID else { return nil }
        return archivedCategories.first(where: { $0.persistentModelID == pendingRestoreCategoryID })
    }

    var body: some View {
        List {
            if archivedCategories.isEmpty {
                ContentUnavailableView(
                    "No Archived Categories",
                    systemImage: "archivebox",
                    description: Text("Archived categories will appear here.")
                )
            } else {
                ForEach(archivedCategories) { category in
                    let restoredName = resolvedRestoreName(for: category)
                    let willRenameOnRestore = restoredName != category.name
                    HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.compact) {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                            Text(category.name)
                                .font(AppDesign.Theme.Typography.body)
                                .fontWeight(.medium)
                            if let archivedAfter = category.archivedAfterMonthStart {
                                let archiveMonth = Calendar.current.date(byAdding: .month, value: 1, to: archivedAfter) ?? archivedAfter
                                Text("Archived from \(archiveMonth.formatted(.dateTime.month(.wide).year()))")
                                    .appCaption2Text()
                                    .foregroundStyle(.secondary)
                            }
                            Text("Default: \(category.assigned.formatted(.currency(code: appSettings.currencyCode)))")
                                .appCaption2Text()
                                .foregroundStyle(.secondary)
                            if willRenameOnRestore {
                                Text("Restores as \"\(restoredName)\"")
                                    .appCaption2Text()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
                                    .padding(.horizontal, AppDesign.Theme.Spacing.small)
                                    .padding(.vertical, AppDesign.Theme.Spacing.hairline)
                                    .background(
                                        Capsule()
                                            .fill(AppDesign.Colors.warning(for: appColorMode).opacity(0.12))
                                    )
                            }
                        }

                        Spacer(minLength: 0)

                        Button {
                            pendingRestoreCategoryID = category.persistentModelID
                            pendingRestoreName = resolvedRestoreName(for: category)
                            showingRestoreConfirmation = true
                        } label: {
                            if restoringCategoryID == category.persistentModelID {
                                ProgressView()
                            } else {
                                Text("Restore")
                                    .font(AppDesign.Theme.Typography.secondaryBody.weight(.semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(restoringCategoryID != nil)
                    }
                    .padding(.vertical, AppDesign.Theme.Spacing.micro)
                }
            }
        }
        .confirmationDialog(
            "Restore category for \(restoreMonthLabel)?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            if let category = pendingRestoreCategory {
                Button("Restore", role: .none) {
                    restoreCategoryFromCurrentMonth(category, restoredName: pendingRestoreName)
                    pendingRestoreCategoryID = nil
                    pendingRestoreName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreCategoryID = nil
                pendingRestoreName = ""
            }
        } message: {
            if let category = pendingRestoreCategory {
                if pendingRestoreName != category.name {
                    Text("An active category with this name already exists. It will be restored as \"\(pendingRestoreName)\".")
                } else {
                    Text("This creates an active copy starting in \(restoreMonthLabel). Historical months remain unchanged.")
                }
            }
        }
    }

    private func resolvedRestoreName(for archivedCategory: Category) -> String {
        let baseName = archivedCategory.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Restored Category"
            : archivedCategory.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let group = archivedCategory.group else { return baseName }

        let activeNames = Set(
            (group.categories ?? [])
                .filter { $0.isActive(inMonthStart: restoreMonthStart) }
                .map { $0.name.lowercased() }
        )

        if !activeNames.contains(baseName.lowercased()) {
            return baseName
        }

        let restoredBase = "\(baseName) (Restored)"
        if !activeNames.contains(restoredBase.lowercased()) {
            return restoredBase
        }

        var suffix = 2
        while true {
            let candidate = "\(baseName) (Restored \(suffix))"
            if !activeNames.contains(candidate.lowercased()) {
                return candidate
            }
            suffix += 1
        }
    }

    private func restoreCategoryFromCurrentMonth(_ archivedCategory: Category, restoredName: String) {
        restoringCategoryID = archivedCategory.persistentModelID
        defer { restoringCategoryID = nil }

        guard let group = archivedCategory.group else { return }
        let nextOrder = ((group.categories ?? []).map(\.order).max() ?? -1) + 1

        let restored = Category(
            name: restoredName,
            assigned: archivedCategory.assigned,
            activity: 0,
            order: nextOrder,
            icon: archivedCategory.icon,
            memo: archivedCategory.memo,
            isDemoData: archivedCategory.isDemoData
        )
        restored.group = group
        restored.budgetTypeRawValue = archivedCategory.budgetTypeRawValue
        restored.overspendHandlingRawValue = archivedCategory.overspendHandlingRawValue
        restored.createdAt = restoreMonthStart
        restored.archivedAfterMonthStart = nil
        restored.savingsGoal = archivedCategory.savingsGoal

        modelContext.insert(restored)

        for monthlyBudget in monthlyCategoryBudgets {
            guard monthlyBudget.category?.persistentModelID == archivedCategory.persistentModelID else { continue }
            guard monthlyBudget.monthStart >= restoreMonthStart else { continue }
            modelContext.insert(
                MonthlyCategoryBudget(
                    monthStart: monthlyBudget.monthStart,
                    amount: monthlyBudget.amount,
                    category: restored,
                    isDemoData: monthlyBudget.isDemoData
                )
            )
        }

        modelContext.safeSave(context: "ArchivedCategoriesSheet.restoreCategory")
        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: restoreMonthStart,
            saveContext: "ArchivedCategoriesSheet.restoreCategory.syncSavingsGoals"
        )
    }
}

private struct ApplyBudgetPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    let initialSourceMonthStart: Date
    let categoryGroups: [CategoryGroup]
    let selectedCategoryIDs: Set<PersistentIdentifier>
    let monthlyCategoryBudgets: [MonthlyCategoryBudget]
    let allStandardTransactions: [Transaction]

    @State private var sourceMonthStart: Date
    @State private var rangeMode: RangeMode = .future
    @State private var rangeMonthCount: Int = 6
    @State private var customFromMonthStart: Date
    @State private var customToMonthStart: Date
    @State private var scopeMode: ScopeMode = .all
    @State private var selectedGroupID: PersistentIdentifier?
    @State private var applyMode: ApplyMode = .replace
    @State private var applying = false
    @State private var applyErrorMessage: String?

    init(
        initialSourceMonthStart: Date,
        categoryGroups: [CategoryGroup],
        selectedCategoryIDs: Set<PersistentIdentifier>,
        monthlyCategoryBudgets: [MonthlyCategoryBudget],
        allStandardTransactions: [Transaction]
    ) {
        self.initialSourceMonthStart = initialSourceMonthStart
        self.categoryGroups = categoryGroups
        self.selectedCategoryIDs = selectedCategoryIDs
        self.monthlyCategoryBudgets = monthlyCategoryBudgets
        self.allStandardTransactions = allStandardTransactions
        _sourceMonthStart = State(initialValue: initialSourceMonthStart)
        _customFromMonthStart = State(initialValue: initialSourceMonthStart)
        _customToMonthStart = State(initialValue: initialSourceMonthStart)
    }

    private enum RangeMode: String, CaseIterable, Identifiable {
        case previous = "Previous"
        case future = "Future"
        case custom = "Custom"

        var id: String { rawValue }
    }

    private enum ScopeMode: String, CaseIterable, Identifiable {
        case all = "All"
        case group = "Group"
        case selected = "Selected"

        var id: String { rawValue }
    }

    private enum ApplyMode: String, CaseIterable, Identifiable {
        case replace = "Replace"
        case fillMissing = "Fill Missing"
        case merge = "Merge Source Overrides"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .replace:
                return "Overwrite target months to match the source month."
            case .fillMissing:
                return "Only fill months that don’t already have a monthly override."
            case .merge:
                return "Apply only categories with a source monthly override; keep other target values."
            }
        }
    }

    private struct BudgetKey: Hashable {
        let categoryID: PersistentIdentifier
        let monthStart: Date
    }

    private enum PlanAction {
        case create(monthStart: Date, amount: Decimal)
        case update(entry: MonthlyCategoryBudget, amount: Decimal)
        case delete(entry: MonthlyCategoryBudget)
    }

    private struct PreviewCounts {
        var createCount: Int = 0
        var updateCount: Int = 0
        var deleteCount: Int = 0
        var skippedInactiveCount: Int = 0

        var totalMutations: Int {
            createCount + updateCount + deleteCount
        }
    }

    private var calendar: Calendar { Calendar.current }

    private var availableGroups: [CategoryGroup] {
        categoryGroups
            .filter { $0.type != .transfer }
            .sorted { $0.order < $1.order }
    }

    private var allTemplateCategories: [Category] {
        availableGroups
            .flatMap { $0.sortedCategories }
            .filter { $0.isActive(inMonthStart: sourceMonthStart) }
    }

    private var scopedCategories: [Category] {
        switch scopeMode {
        case .all:
            return allTemplateCategories
        case .group:
            guard let selectedGroupID else { return [] }
            return allTemplateCategories.filter { $0.group?.persistentModelID == selectedGroupID }
        case .selected:
            return allTemplateCategories.filter { selectedCategoryIDs.contains($0.persistentModelID) }
        }
    }

    private var rangeMonths: [Date] {
        switch rangeMode {
        case .previous:
            return (1...rangeMonthCount)
                .compactMap { calendar.date(byAdding: .month, value: -$0, to: sourceMonthStart) }
                .sorted()
        case .future:
            return (1...rangeMonthCount)
                .compactMap { calendar.date(byAdding: .month, value: $0, to: sourceMonthStart) }
                .sorted()
        case .custom:
            let from = min(customFromMonthStart, customToMonthStart)
            let to = max(customFromMonthStart, customToMonthStart)
            var cursor = from
            var months: [Date] = []
            while cursor <= to {
                if cursor != sourceMonthStart {
                    months.append(cursor)
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            return months
        }
    }

    private var existingOverrideByKey: [BudgetKey: MonthlyCategoryBudget] {
        var map: [BudgetKey: MonthlyCategoryBudget] = [:]
        for entry in monthlyCategoryBudgets {
            guard let categoryID = entry.category?.persistentModelID else { continue }
            map[BudgetKey(categoryID: categoryID, monthStart: normalizedMonthStart(entry.monthStart))] = entry
        }
        return map
    }

    private var sourceOverrideByCategoryID: [PersistentIdentifier: MonthlyCategoryBudget] {
        var map: [PersistentIdentifier: MonthlyCategoryBudget] = [:]
        let source = normalizedMonthStart(sourceMonthStart)
        for entry in monthlyCategoryBudgets {
            guard let categoryID = entry.category?.persistentModelID else { continue }
            guard normalizedMonthStart(entry.monthStart) == source else { continue }
            map[categoryID] = entry
        }
        return map
    }

    private var templateSourceMonths: [Date] {
        let months = Set(
            monthlyCategoryBudgets.compactMap { entry -> Date? in
                guard entry.category != nil else { return nil }
                return normalizedMonthStart(entry.monthStart)
            }
        )
        return months.sorted(by: >)
    }

    private var preview: PreviewCounts {
        let existingByKey = existingOverrideByKey
        let sourceByCategory = sourceOverrideByCategoryID
        return buildPreview(
            categories: scopedCategories,
            months: rangeMonths,
            existingByKey: existingByKey,
            sourceByCategory: sourceByCategory
        )
    }

    private var canApply: Bool {
        !applying &&
        !templateSourceMonths.isEmpty &&
        !scopedCategories.isEmpty &&
        !rangeMonths.isEmpty
    }

    private var previewTransactionCount: Int {
        guard !rangeMonths.isEmpty, !scopedCategories.isEmpty else { return 0 }
        let categoryIDs = Set(scopedCategories.map(\.persistentModelID))
        let monthStarts = Set(rangeMonths.map(normalizedMonthStart))
        return allStandardTransactions.reduce(into: 0) { count, tx in
            guard let categoryID = tx.category?.persistentModelID else { return }
            guard categoryIDs.contains(categoryID) else { return }
            let txMonthStart = normalizedMonthStart(tx.date)
            if monthStarts.contains(txMonthStart) {
                count += 1
            }
        }
    }

    var body: some View {
        Form {
            if let applyErrorMessage {
                Section {
                    Text(applyErrorMessage)
                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                }
            }

            Section("Template Source") {
                templateSourceMonthPicker()

                Text("Uses monthly override if present for source month; otherwise category default amount.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Section("Target Range") {
                Picker("Range", selection: $rangeMode) {
                    ForEach(RangeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch rangeMode {
                case .previous, .future:
                    Stepper("Months: \(rangeMonthCount)", value: $rangeMonthCount, in: 1...36)
                case .custom:
                    monthYearPicker("From", date: $customFromMonthStart)
                    monthYearPicker("To", date: $customToMonthStart)
                }
            }

            Section("Scope") {
                Picker("Apply To", selection: $scopeMode) {
                    ForEach(ScopeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if scopeMode == .group {
                    Picker("Group", selection: $selectedGroupID) {
                        Text("Select Group").tag(Optional<PersistentIdentifier>.none)
                        ForEach(availableGroups) { group in
                            Text(group.name).tag(Optional(group.persistentModelID))
                        }
                    }
                }

                if scopeMode == .selected {
                    Text(selectedCategoryIDs.isEmpty
                         ? "No categories selected. Use Bulk Select first, then reopen this sheet."
                         : "Selected categories: \(selectedCategoryIDs.count)")
                        .appCaptionText()
                        .foregroundStyle(selectedCategoryIDs.isEmpty ? AppDesign.Colors.warning(for: appColorMode) : .secondary)
                }
            }

            Section("Behavior") {
                Picker("Apply Mode", selection: $applyMode) {
                    ForEach(ApplyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Text(applyMode.description)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                HStack {
                    Text("Target Months")
                    Spacer()
                    Text("\(rangeMonths.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Scoped Categories")
                    Spacer()
                    Text("\(scopedCategories.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Transactions in Range")
                    Spacer()
                    Text("\(previewTransactionCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Create (new monthly entries)")
                    Spacer()
                    Text("\(preview.createCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Update (change existing entries)")
                    Spacer()
                    Text("\(preview.updateCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Delete (remove previous entries)")
                    Spacer()
                    Text("\(preview.deleteCount)")
                        .foregroundStyle(.secondary)
                }
                if preview.skippedInactiveCount > 0 {
                    HStack {
                        Text("Skipped (Inactive)")
                        Spacer()
                        Text("\(preview.skippedInactiveCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Apply Budget Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(applying ? "Applying…" : "Apply") {
                    applyPlan()
                }
                .disabled(!canApply)
            }
        }
        .onAppear {
            if let currentMonth = templateSourceMonths.first(where: { $0 == normalizedMonthStart(sourceMonthStart) }) {
                sourceMonthStart = currentMonth
            } else if let latestTemplateMonth = templateSourceMonths.first {
                sourceMonthStart = latestTemplateMonth
            }
            if selectedGroupID == nil {
                selectedGroupID = availableGroups.first?.persistentModelID
            }
        }
    }

    private func normalizedMonthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.monthSymbols
    }

    private var availableYears: [Int] {
        let yearsFromTransactions = allStandardTransactions.map { calendar.component(.year, from: $0.date) }
        let yearsFromOverrides = monthlyCategoryBudgets.map { calendar.component(.year, from: $0.monthStart) }
        let sourceYear = calendar.component(.year, from: sourceMonthStart)
        let minYear = min((yearsFromTransactions + yearsFromOverrides).min() ?? sourceYear, sourceYear - 5)
        let maxYear = max((yearsFromTransactions + yearsFromOverrides).max() ?? sourceYear, sourceYear + 5)
        return Array(minYear...maxYear)
    }

    @ViewBuilder
    private func monthYearPicker(_ title: String, date: Binding<Date>) -> some View {
        let monthBinding = Binding<Int>(
            get: { calendar.component(.month, from: normalizedMonthStart(date.wrappedValue)) },
            set: { newMonth in
                var components = calendar.dateComponents([.year], from: normalizedMonthStart(date.wrappedValue))
                components.month = newMonth
                components.day = 1
                if let updated = calendar.date(from: components) {
                    date.wrappedValue = normalizedMonthStart(updated)
                }
            }
        )

        let yearBinding = Binding<Int>(
            get: { calendar.component(.year, from: normalizedMonthStart(date.wrappedValue)) },
            set: { newYear in
                var components = calendar.dateComponents([.month], from: normalizedMonthStart(date.wrappedValue))
                components.year = newYear
                components.day = 1
                if let updated = calendar.date(from: components) {
                    date.wrappedValue = normalizedMonthStart(updated)
                }
            }
        )

        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)
            HStack(spacing: AppDesign.Theme.Spacing.tight) {
                Picker("Month", selection: monthBinding) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthSymbols[month - 1]).tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .frame(height: 110)

                Picker("Year", selection: yearBinding) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            }
        }
    }

    @ViewBuilder
    private func templateSourceMonthPicker() -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
            Text("Source Month")
                .appCaptionText()
                .foregroundStyle(.secondary)

            if templateSourceMonths.isEmpty {
                Text("No months with budget data found.")
                    .appCaptionText()
                    .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
            } else {
                let selectedMonthBinding = Binding<Date>(
                    get: { normalizedMonthStart(sourceMonthStart) },
                    set: { sourceMonthStart = normalizedMonthStart($0) }
                )

                Picker("Source Month", selection: selectedMonthBinding) {
                    ForEach(templateSourceMonths, id: \.self) { month in
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        }
    }

    private func isInactiveForTargetMonth(_ category: Category, month: Date) -> Bool {
        // Allow historical backfill to months at/before the source month even if the
        // category was technically created later; this is the primary backfill use case.
        if month <= sourceMonthStart {
            return false
        }
        return !category.isActive(inMonthStart: month)
    }

    private func buildPreview(
        categories: [Category],
        months: [Date],
        existingByKey: [BudgetKey: MonthlyCategoryBudget],
        sourceByCategory: [PersistentIdentifier: MonthlyCategoryBudget]
    ) -> PreviewCounts {
        var counts = PreviewCounts()
        for category in categories {
            let sourceOverride = sourceByCategory[category.persistentModelID]
            let sourceHasOverride = sourceOverride != nil
            let sourceAmount = sourceOverride?.amount ?? category.assigned

            for month in months {
                guard !isInactiveForTargetMonth(category, month: month) else {
                    counts.skippedInactiveCount += 1
                    continue
                }
                let key = BudgetKey(categoryID: category.persistentModelID, monthStart: month)
                let existing = existingByKey[key]
                if let action = resolveAction(
                    monthStart: month,
                    existing: existing,
                    sourceAmount: sourceAmount,
                    sourceHasOverride: sourceHasOverride
                ) {
                    switch action {
                    case .create:
                        counts.createCount += 1
                    case .update:
                        counts.updateCount += 1
                    case .delete:
                        counts.deleteCount += 1
                    }
                }
            }
        }
        return counts
    }

    private func resolveAction(
        monthStart: Date,
        existing: MonthlyCategoryBudget?,
        sourceAmount: Decimal,
        sourceHasOverride: Bool
    ) -> PlanAction? {
        switch applyMode {
        case .replace:
            return makeExplicitSetAction(existing: existing, monthStart: monthStart, targetAmount: sourceAmount)

        case .fillMissing:
            guard existing == nil else { return nil }
            return .create(monthStart: monthStart, amount: sourceAmount)

        case .merge:
            guard sourceHasOverride else { return nil }
            return makeExplicitSetAction(existing: existing, monthStart: monthStart, targetAmount: sourceAmount)
        }
    }

    private func makeExplicitSetAction(
        existing: MonthlyCategoryBudget?,
        monthStart: Date,
        targetAmount: Decimal
    ) -> PlanAction? {
        if let existing {
            if existing.amount == targetAmount { return nil }
            return .update(entry: existing, amount: targetAmount)
        }
        return .create(monthStart: monthStart, amount: targetAmount)
    }

    private func applyPlan() {
        applyErrorMessage = nil
        applying = true
        defer { applying = false }

        let months = rangeMonths
        let categories = scopedCategories
        guard !months.isEmpty else {
            applyErrorMessage = "No target months selected."
            return
        }
        guard !categories.isEmpty else {
            applyErrorMessage = "No categories found for the selected scope and source month."
            return
        }

        var existingByKey = existingOverrideByKey
        let sourceByCategory = sourceOverrideByCategoryID
        var didMutate = false

        for category in categories {
            let sourceOverride = sourceByCategory[category.persistentModelID]
            let sourceHasOverride = sourceOverride != nil
            let sourceAmount = sourceOverride?.amount ?? category.assigned

            for month in months {
                guard !isInactiveForTargetMonth(category, month: month) else { continue }
                let key = BudgetKey(categoryID: category.persistentModelID, monthStart: month)
                let existing = existingByKey[key]

                let action: PlanAction?
                switch applyMode {
                case .replace:
                    action = makeExplicitSetAction(existing: existing, monthStart: month, targetAmount: sourceAmount)
                case .fillMissing:
                    if existing == nil {
                        action = .create(monthStart: month, amount: sourceAmount)
                    } else {
                        action = nil
                    }
                case .merge:
                    if sourceHasOverride {
                        action = makeExplicitSetAction(existing: existing, monthStart: month, targetAmount: sourceAmount)
                    } else {
                        action = nil
                    }
                }

                guard let action else { continue }
                switch action {
                case let .create(monthStart, amount):
                    let entry = MonthlyCategoryBudget(
                        monthStart: monthStart,
                        amount: amount,
                        category: category,
                        isDemoData: category.isDemoData
                    )
                    modelContext.insert(entry)
                    existingByKey[key] = entry
                    didMutate = true

                case let .update(entry, amount):
                    entry.amount = amount
                    didMutate = true

                case let .delete(entry):
                    modelContext.delete(entry)
                    existingByKey.removeValue(forKey: key)
                    didMutate = true
                }
            }
        }

        if !didMutate {
            InAppNotificationService.post(
                title: "No Changes Applied",
                message: "Target months already match the selected source and mode.",
                type: .info,
                in: modelContext,
                topic: .budgetAlerts
            )
            dismiss()
            return
        }
        guard modelContext.safeSave(context: "ApplyBudgetPlanSheet.applyPlan") else {
            applyErrorMessage = "Couldn't apply the budget plan. Please try again."
            return
        }
        DataChangeTracker.bump()
        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: sourceMonthStart,
            saveContext: "ApplyBudgetPlanSheet.applyPlan.syncSavingsGoals"
        )
        let monthsCount = months.count
        InAppNotificationService.post(
            title: "Budget Plan Applied",
            message: "Updated \(categories.count) categories across \(monthsCount) month\(monthsCount == 1 ? "" : "s").",
            type: .success,
            in: modelContext,
            topic: .budgetAlerts
        )
        dismiss()
    }
}

private struct BudgetActionsSheet: View {

    @Environment(\.appSettings) private var appSettings
    let canUndo: Bool
    let canRedo: Bool
    let isBulkSelecting: Bool
    let isReordering: Bool
    let hasGroups: Bool
    let currentSort: BudgetView.GroupSortOption
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSetUpBudget: () -> Void
    let onApplyBudgetPlan: () -> Void
    let onSort: (BudgetView.GroupSortOption) -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void
    let onToggleBulkSelect: () -> Void
    let onToggleReorder: () -> Void
    let archivedCategoryCount: Int
    let onManageArchived: () -> Void
    let onAddGroup: () -> Void
    let onAddCategory: () -> Void

    var body: some View {
        List {
            Section("Create") {
                Button {
                    onAddGroup()
                } label: {
                    actionRow(title: "Add Category Group", systemImage: "folder.badge.plus")
                }

                Button {
                    onAddCategory()
                } label: {
                    actionRow(title: "Add Category", systemImage: "plus.circle")
                }
            }

            Section("Budget") {
                Button {
                    onSetUpBudget()
                } label: {
                    actionRow(title: "Initial Budget Set up", systemImage: "slider.horizontal.3")
                }

                Button {
                    onApplyBudgetPlan()
                } label: {
                    actionRow(title: "Apply Budget Plan", systemImage: "calendar.badge.clock")
                }
            }

            Section("Organize") {
                NavigationLink {
                    List {
                        ForEach(BudgetView.GroupSortOption.allCases, id: \.rawValue) { option in
                            Button {
                                onSort(option)
                            } label: {
                                HStack {
                                    Text(option.title)
                                    Spacer()
                                    if option == currentSort {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Sort Groups")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    actionRow(title: "Sort Groups", systemImage: "arrow.up.arrow.down")
                }

                Button {
                    onExpandAll()
                } label: {
                    actionRow(title: "Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(!hasGroups)

                Button {
                    onCollapseAll()
                } label: {
                    actionRow(title: "Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(!hasGroups)
                
                Button {
                    onToggleBulkSelect()
                } label: {
                    actionRow(
                        title: isBulkSelecting ? "Done Selecting" : "Bulk Select",
                        systemImage: isBulkSelecting ? "checkmark.circle" : "checkmark.circle.badge.plus"
                    )
                }

                Button {
                    onToggleReorder()
                } label: {
                    actionRow(
                        title: isReordering ? "Done Reordering" : "Reorder",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            }

            Section("Categories") {
                Button {
                    onManageArchived()
                } label: {
                    HStack {
                        Label("Archived Categories", systemImage: "archivebox")
                        if archivedCategoryCount > 0 {
                            Spacer()
                            Text("\(archivedCategoryCount)")
                                .appCaptionText()
                                .fontWeight(.semibold)
                                .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
                                .padding(.vertical, AppDesign.Theme.Spacing.hairline)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                )
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("History") {
                Button {
                    onUndo()
                } label: {
                    actionRow(title: "Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)

                Button {
                    onRedo()
                } label: {
                    actionRow(title: "Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
            }
        }
        .environment(\.symbolRenderingMode, .monochrome)
        .tint(.primary)
    }

    @ViewBuilder
    private func actionRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}

#Preview {
    BudgetView(searchText: .constant(""))
        .modelContainer(for: [CategoryGroup.self, Category.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
