import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager
    @Environment(\.appColorMode) private var appColorMode

    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "standard"
        },
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var allStandardTransactions: [Transaction]

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("budgetAlerts") private var budgetAlerts = true

    @State private var selectedDate = Date()
    @Binding var searchText: String
    @State private var isMonthHeaderCompact = false
    
    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var editMode: EditMode = .inactive
    @State private var showingGroupSelection = false
    @State private var showingAddCategory = false
    @State private var selectedGroupForNewCategory: CategoryGroup?
    @State private var newCategoryName = ""
    @State private var newCategoryBudget = ""
    @State private var selectedCategoryForEdit: Category?
    @State private var movingCategory: Category?
    @State private var collapsedGroups: Set<ObjectIdentifier> = []
    @State private var showingBudgetSetupWizard = false
    @State private var showingBudgetResetConfirm = false

    @State private var isBulkSelecting = false
    @State private var selectedCategoryIDs: Set<PersistentIdentifier> = []
    @State private var bulkSelectionType: CategoryGroupType?
    @State private var showingBulkMoveSheet = false
    @State private var showingSelectionTypeMismatchAlert = false

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
        let cats = group.sortedCategories
        guard isSearching else { return cats }
        return cats.filter(matchesSearch(_:))
    }

    private var hasAnySearchResults: Bool {
        guard isSearching else { return true }
        return categoryGroups.contains(where: matchesSearch(_:))
    }

    private var monthChromeCornerRadius: CGFloat {
        isMonthHeaderCompact ? 18 : 22
    }

    private var monthChromeSpacerHeight: CGFloat {
        // Space reserved at top of the list so the floating month header doesn't cover first rows.
        isMonthHeaderCompact ? 64 : 74
    }

    // MARK: - Computed Data (Replaces N+1 Query Pattern)

    /// Transactions for the selected month (computed once per render)
    private var monthTransactions: [Transaction] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? selectedDate

        return allStandardTransactions.filter { tx in
            tx.date >= start &&
            tx.date < end &&
            tx.account?.isTrackingOnly != true
        }
    }

    /// Transactions grouped by category ID for efficient lookup (computed once per render)
    /// Replaces the N+1 anti-pattern where each row filtered all transactions
    private var transactionsByCategory: [PersistentIdentifier: [Transaction]] {
        var grouped: [PersistentIdentifier: [Transaction]] = [:]
        grouped.reserveCapacity(categoryGroups.flatMap { $0.categories ?? [] }.count)

        for transaction in monthTransactions {
            if let categoryID = transaction.category?.persistentModelID {
                grouped[categoryID, default: []].append(transaction)
            }
        }

        return grouped
    }

    private var monthChromeView: some View {
        MonthNavigationHeader(selectedDate: $selectedDate, isCompact: isMonthHeaderCompact)
            .padding(.horizontal, 12)
            .padding(.vertical, isMonthHeaderCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: monthChromeCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: monthChromeCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }
    
    var body: some View {
        List {
            Color.clear
                .frame(height: monthChromeSpacerHeight)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            budgetListContent
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .coordinateSpace(name: "BudgetView.scroll")
            .background(ScrollOffsetEmitter(id: "BudgetView.scroll", emitLegacy: true))
            .task(id: selectedDate) {
                // Post budget alerts when month changes
                let calendar = Calendar.current
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
                postBudgetAlertsIfNeeded(for: selectedDate, monthTransactions: monthTransactions, startOfMonth: startOfMonth)
            }
            .overlay(alignment: .top) {
                monthChromeView
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                let shouldCompact = offset < -12
                if shouldCompact != isMonthHeaderCompact {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isMonthHeaderCompact = shouldCompact
                    }
                }
            }
            .toolbar {
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

                        Button("Set Up Budget") {
                            showingBudgetResetConfirm = true
                        }

                        Divider()

                        Menu {
                            ForEach(GroupSortOption.allCases, id: \.rawValue) { option in
                                Button {
                                    applyGroupSort(option)
                                } label: {
                                    if option == groupSortOption {
                                        Label(option.title, systemImage: "checkmark")
                                    } else {
                                        Text(option.title)
                                    }
                                }
                            }
                        } label: {
                            Label("Sort Groups", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        Button("Expand All") {
                            withAnimation {
                                collapsedGroups.removeAll()
                            }
                        }
                        .disabled(categoryGroups.isEmpty)

                        Button("Collapse All") {
                            withAnimation {
                                collapsedGroups = Set(categoryGroups.map { ObjectIdentifier($0) })
                            }
                        }
                        .disabled(categoryGroups.isEmpty)

                        Divider()

                        Button(isBulkSelecting ? "Done Selecting" : "Bulk Select") {
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
                        }

                        Divider()

                        Button(action: {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }) {
                            Label(editMode == .active ? "Done Reordering" : "Reorder", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        Button("Add Category Group") {
                            showingAddGroup = true
                        }

                        Button("Add Category") {
                            showingGroupSelection = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                }
            }
            .confirmationDialog("Select Group for Category", isPresented: $showingGroupSelection) {
                ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                    Button(group.name) {
                        selectedGroupForNewCategory = group
                        showingAddCategory = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .fullScreenCover(item: $selectedCategoryForEdit) { category in
                CategoryEditSheet(category: category) {
                    selectedCategoryForEdit = nil
                }
            }
            .sheet(item: $movingCategory) { category in
                MoveCategorySheet(category: category)
            }
            .sheet(isPresented: $showingBulkMoveSheet) {
                if let bulkSelectionType {
                    BulkMoveCategoriesSheet(
                        categoryIDs: Array(selectedCategoryIDs),
                        requiredType: bulkSelectionType
                    )
                }
            }
            .alert("New Category Group", isPresented: $showingAddGroup) {
                TextField("Group Name", text: $newGroupName)
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    addGroup()
                }
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("Category Name", text: $newCategoryName)
                TextField("Budget Amount", text: $newCategoryBudget)
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
            .confirmationDialog(
                "Set Up Budget",
                isPresented: $showingBudgetResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Set Up Budget") { showingBudgetSetupWizard = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Use guided setup to rebuild your budget groups and categories.")
            }
            .sheet(isPresented: $showingBudgetSetupWizard) {
                BudgetSetupWizardView(replaceExistingDefault: true)
            }
            .alert("Selection", isPresented: $showingSelectionTypeMismatchAlert) {
                Button("OK") { }
            } message: {
                Text("You can only bulk select income or expense categories at a time.")
            }
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
                        if value.translation.width < -50 {
                            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = nextMonth
                                }
                            }
                        }
                        // Swipe right (previous month)
                        else if value.translation.width > 50 {
                            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = previousMonth
                                }
                            }
                        }
                    }
            , including: .gesture)
    }

    private func postBudgetAlertsIfNeeded(for month: Date, monthTransactions: [Transaction], startOfMonth: Date) {
        guard budgetAlerts else { return }

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
            guard category.assigned > 0 else { continue }

            let net = monthTransactions
                .filter { $0.category?.id == category.persistentModelID }
                .reduce(Decimal.zero) { $0 + $1.amount }

            let spent = max(Decimal.zero, -net)
            guard spent > 0 else { continue }

            let remaining = category.assigned - spent
            let assignedDouble = NSDecimalNumber(decimal: category.assigned).doubleValue
            let ratio = assignedDouble > 0 ? NSDecimalNumber(decimal: spent).doubleValue / assignedDouble : 0

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
        formatter.currencyCode = currencyCode
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

    @ViewBuilder
    private var budgetListContent: some View {
        if isSearching, !hasAnySearchResults {
            ContentUnavailableView.search(text: searchText)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            incomeGroupSection

            ForEach(expenseGroupsForList) { group in
                expenseGroupSection(group)
            }
            .onMove(perform: moveGroups)
        }
    }

    @ViewBuilder
    private var incomeGroupSection: some View {
        if let incomeGroup = categoryGroups.first(where: { $0.type == .income }),
           !incomeGroup.sortedCategories.isEmpty,
           matchesSearch(incomeGroup) {
            Section(
                header: GroupHeaderView(
                    group: incomeGroup,
                    isCollapsed: isSearching ? false : isGroupCollapsed(incomeGroup),
                    onToggleCollapse: { toggleGroupCollapse(incomeGroup) }
                )
                .foregroundColor(AppColors.success(for: appColorMode))
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
                            .foregroundColor(AppColors.success(for: appColorMode))
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func expenseGroupSection(_ group: CategoryGroup) -> some View {
        Section(
            header: GroupHeaderView(
                group: group,
                isCollapsed: isSearching ? false : isGroupCollapsed(group),
                onToggleCollapse: { toggleGroupCollapse(group) }
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
                        .foregroundColor(AppColors.tint(for: appColorMode))
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            }
        }
    }

    private func categoryRow(for category: Category) -> some View {
        let isSelected = selectedCategoryIDs.contains(category.persistentModelID)
        // Pass only transactions for THIS category (pre-grouped) - no filtering needed
        let categoryTransactions = transactionsByCategory[category.persistentModelID] ?? []
        let row = BudgetCategoryRowView(
            category: category,
            selectedDate: selectedDate,
            transactions: categoryTransactions,
            showsSelection: isBulkSelecting,
            isSelected: isSelected
        ) {
            if isBulkSelecting {
                toggleSelection(for: category)
            } else {
                selectedCategoryForEdit = category
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
                    .tint(AppColors.tint(for: appColorMode))
                }
                .swipeActions(edge: HorizontalEdge.trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        movingCategory = category
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(AppColors.tint(for: appColorMode))
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    Haptics.impact(.medium)
                    selectedCategoryForEdit = category
                }
        )
    }

    private var bulkSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(selectedCategoryIDs.isEmpty ? "Select All" : "Clear") {
                    withAnimation {
                        if selectedCategoryIDs.isEmpty {
                            selectAllVisibleCategories()
                        } else {
                            selectedCategoryIDs.removeAll()
                            bulkSelectionType = nil
                        }
                    }
                }

                Spacer()

                Button("Move…") {
                    showingBulkMoveSheet = true
                }
                .fontWeight(.semibold)
                .disabled(selectedCategoryIDs.isEmpty || bulkSelectionType == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial)
        }
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

        if let incomeGroup = categoryGroups.first(where: { $0.type == .income }),
           !incomeGroup.sortedCategories.isEmpty,
           matchesSearch(incomeGroup),
           (isSearching || !isGroupCollapsed(incomeGroup)) {
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
                        type: .expense
                    )
                )
            } catch {
                // Fallback
                let newGroup = CategoryGroup(name: trimmed, order: maxOrder + 1)
                modelContext.insert(newGroup)
                modelContext.safeSave(context: "BudgetView.addGroup.fallback")
            }
            newGroupName = ""
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
            newCategory.group = group
            modelContext.insert(newCategory)
            modelContext.safeSave(context: "BudgetView.addCategory.fallback")
        }
    }
    
    private func deleteCategory(_ category: Category) {
        withAnimation {
            do {
                try undoRedoManager.execute(
                    DeleteCategoryCommand(modelContext: modelContext, category: category)
                )
            } catch {
                modelContext.delete(category)
                modelContext.safeSave(context: "BudgetView.deleteCategory.fallback")
            }
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
    let group: CategoryGroup
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var newName = ""
    
    var body: some View {
        let totalAssigned = (group.categories ?? []).reduce(0) { $0 + $1.assigned }
        
        HStack(spacing: 8) {
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand \(group.name)" : "Collapse \(group.name)")
            
            HStack(spacing: 6) {
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(totalAssigned, format: .currency(code: currencyCode))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
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
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
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
    let category: Category
    let selectedDate: Date
    let transactions: [Transaction]
    let showsSelection: Bool
    let isSelected: Bool
    let onTap: () -> Void
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    private var monthlyData: (spent: Decimal, remaining: Decimal) {
        // Transactions are already filtered by category and month - just compute totals
        let net = transactions.reduce(Decimal.zero) { $0 + $1.amount }

        // For expense, net is negative. Spent is positive abs(net).
        // For income, net is positive. "Spent" isn't really the term, but activity.
        if category.group?.type == .income {
            return (spent: net, remaining: 0) // Income just shows what came in
        } else {
            let spent = max(Decimal.zero, -net)
            return (spent: spent, remaining: category.assigned - spent)
        }
    }
    
    init(
        category: Category,
        selectedDate: Date,
        transactions: [Transaction],
        showsSelection: Bool = false,
        isSelected: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.category = category
        self.selectedDate = selectedDate
        self.transactions = transactions
        self.showsSelection = showsSelection
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Category icon
                Circle()
                    .fill(AppColors.tint(for: appColorMode).opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(category.icon ?? String(category.name.prefix(1)).uppercased())
                            .font(.system(size: category.icon != nil ? 20 : 16, weight: .semibold))
                            .foregroundColor(AppColors.tint(for: appColorMode))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if category.assigned == 0 && category.group?.type != .income {
                        Text("Needs Budget")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.warning(for: appColorMode))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(category.assigned, format: .currency(code: currencyCode))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    if category.group?.type == .income {
                        if monthlyData.spent > 0 {
                            Text("Received: \(monthlyData.spent.formatted(.currency(code: currencyCode)))")
                                .font(.caption2)
                                .foregroundColor(AppColors.success(for: appColorMode))
                        }
                    } else {
                        if category.assigned > 0 {
                            let remaining = monthlyData.remaining
                            Text("\(remaining >= 0 ? "Left" : "Over"): \(abs(remaining).formatted(.currency(code: currencyCode)))")
                                .font(.caption2)
                            .foregroundColor(remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode))
                        } else if monthlyData.spent > 0 {
                            Text("Spent: \(monthlyData.spent.formatted(.currency(code: currencyCode)))")
                                .font(.caption2)
                                .foregroundColor(AppColors.danger(for: appColorMode))
                        }
                    }
                }
                
                if showsSelection {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AppColors.tint(for: appColorMode) : Color.secondary.opacity(0.35))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}


// MARK: - Category Transactions Sheet

struct CategoryTransactionsSheet: View {
    let category: Category
    let transactions: [Transaction]
    let dateRange: (start: Date, end: Date)
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.appColorMode) private var appColorMode
    @State private var sortOption: SortOption = .dateNewest
    @State private var selectedTransaction: Transaction?
    
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
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("Budget")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(category.assigned, format: .currency(code: currencyCode))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        
                        Divider()
                            .frame(height: 40)
                        
                        VStack(spacing: 4) {
                            Text("Spent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(totalSpent, format: .currency(code: currencyCode))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.danger(for: appColorMode))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        
                        Divider()
                            .frame(height: 40)
                        
                        VStack(spacing: 4) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(category.assigned - totalSpent, format: .currency(code: currencyCode))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor((category.assigned - totalSpent) >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    
                    // Date range
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM d, yyyy"
                    Text("\(formatter.string(from: dateRange.start)) – \(formatter.string(from: dateRange.end))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                if transactions.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No transactions")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Transactions in this category will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(sortedTransactions) { transaction in
                            Button {
                                selectedTransaction = transaction
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transaction.payee)
                                            .font(.body)
                                            .fontWeight(.medium)

                                        HStack(spacing: 8) {
                                            Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            if let account = transaction.account {
                                                Text(account.name)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Text(transaction.amount, format: .currency(code: currencyCode))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    .sheet(item: $selectedTransaction) { transaction in
                        TransactionFormView(transaction: transaction)
                    }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Category Edit Sheet

struct CategoryEditSheet: View {
    let category: Category
    let onDismiss: () -> Void
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
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
    @State private var memoText: String = ""
    @State private var icon: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Category Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $name)
                            .font(.body)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Budget Amount")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Amount", value: $assigned, format: .currency(code: currencyCode))
                            .keyboardType(.decimalPad)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Memo (Optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Add a note...", text: $memoText)
                    }
                } header: {
                    Text("Details")
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
                                .font(.caption)
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
                                    .font(.title2)
                            }
                        } else {
                            Button(action: { showingEmojiPicker = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppColors.tint(for: appColorMode))
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
                            Label("Delete Category", systemImage: "trash")
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
                "Delete \"\(category.name)\"?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    do {
                        try undoRedoManager.execute(
                            DeleteCategoryCommand(modelContext: modelContext, category: category)
                        )
                    } catch {
                        modelContext.delete(category)
                        modelContext.safeSave(context: "CategoryEditorSheet.deleteCategory.fallback")
                    }
                    onDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete this category and cannot be undone.")
            }
        }
        .onAppear {
            name = category.name
            assigned = category.assigned
            memoText = category.memo ?? ""
            icon = category.icon
            syncBudgetSectionFromCategory()
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

        do {
            try undoRedoManager.execute(
                UpdateCategoryCommand(
                    modelContext: modelContext,
                    category: category,
                    newName: finalName,
                    newAssigned: assigned,
                    newActivity: category.activity,
                    newOrder: category.order,
                    newIcon: icon,
                    newMemo: finalMemo,
                    newGroup: category.group
                )
            )
        } catch {
            category.name = finalName
            category.assigned = assigned
            category.icon = icon
            category.memo = finalMemo
            modelContext.safeSave(context: "CategoryEditorSheet.saveChanges.fallback")
        }
    }
}

struct EmojiPickerSheet: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    var categoryName: String? = nil

    @State private var searchText: String = ""
    @State private var customEmojiText: String = ""
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
        let base = [categoryName, searchText].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }
        return EmojiSuggester.suggest(for: base)
    }

    private var customEmojiCandidate: String? {
        customEmojiText.firstEmojiString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Search (e.g., groceries, rent, travel)", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Any emoji")
                                .font(.headline)
                                .padding(.horizontal)

                            HStack(spacing: 10) {
                                TextField("Type or paste an emoji", text: $customEmojiText)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($customEmojiFocused)
                                    .onSubmit {
                                        if let candidate = customEmojiCandidate {
                                            selectedEmoji = candidate
                                            dismiss()
                                        }
                                    }

                                if let candidate = customEmojiCandidate {
                                    Button {
                                        selectedEmoji = candidate
                                        dismiss()
                                    } label: {
                                        Text(candidate)
                                            .font(.system(size: 28))
                                            .frame(width: 44, height: 44)
                                            .background(AppColors.tint(for: appColorMode).opacity(0.15))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Use emoji \(candidate)")
                                } else {
                                    Button {
                                        customEmojiFocused = true
                                    } label: {
                                        Image(systemName: "face.smiling")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open emoji keyboard")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !suggestedEmojis.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggested")
                                .font(.headline)
                                .padding(.horizontal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: 10) {
                                ForEach(suggestedEmojis, id: \.self) { emoji in
                                    Button {
                                        selectedEmoji = emoji
                                        dismiss()
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 32))
                                            .frame(width: 45, height: 45)
                                            .background(selectedEmoji == emoji ? AppColors.tint(for: appColorMode).opacity(0.2) : Color.clear)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    ForEach(filteredCategories, id: \.0) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.0)
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: 10) {
                                ForEach(category.1, id: \.self) { emoji in
                                    Button(action: {
                                        selectedEmoji = emoji
                                        dismiss()
                                    }) {
                                        Text(emoji)
                                            .font(.system(size: 32))
                                            .frame(width: 45, height: 45)
                                            .background(selectedEmoji == emoji ? AppColors.tint(for: appColorMode).opacity(0.2) : Color.clear)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Option to clear
                    Button(action: {
                        selectedEmoji = nil
                        dismiss()
                    }) {
                        Label("Remove Icon", systemImage: "trash")
                            .foregroundColor(AppColors.danger(for: appColorMode))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding()
                }
                .padding(.vertical)
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
    }

    private var filteredCategories: [(String, [String])] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return categories.filter { $0.0 != "Suggested" }
        }

        // If the user types an emoji, just show everything (they can tap the emoji itself above).
        if trimmed.firstEmojiString != nil {
            return categories.filter { $0.0 != "Suggested" }
        }

        let lower = trimmed.lowercased()
        return categories
            .filter { $0.0 != "Suggested" }
            .map { title, emojis in
                let keep = emojis
                return (title, keep)
            }
            .filter { title, _ in title.lowercased().contains(lower) || EmojiSuggester.matchesCategoryTitle(lower, title: title) }
    }
}

#Preview {
    BudgetView(searchText: .constant(""))
        .modelContainer(for: [CategoryGroup.self, Category.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
