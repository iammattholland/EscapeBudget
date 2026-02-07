import SwiftUI
import SwiftData

struct QuickCategorizeView: View {
    @Bindable var transaction: Transaction
    let currencyCode: String
    var categoryGroups: [CategoryGroup]
    var onCategorize: (Category) -> Void
    var onSkip: () -> Void
    var onManual: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    
    @State private var offset: CGSize = .zero
    @State private var suggestions: (top: Category?, bottom: Category?) = (nil, nil)
    @State private var transferCounterpartyName: String?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: AppDesign.Theme.Spacing.medium) {
                    HStack(spacing: AppDesign.Theme.Spacing.medium) {
                        Button(action: triggerSkip) {
                            SwipeOptionLabel(text: "Skip", color: .gray, icon: "arrow.left")
                        }
                        .buttonStyle(.plain)

                        if let top = suggestions.top {
                            Button {
                                onCategorize(top)
                            } label: {
                                SwipeOptionLabel(text: top.name, color: AppDesign.Colors.tint(for: appColorMode), icon: "arrow.up")
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()

                        Button {
                            onManual()
                        } label: {
                            SwipeOptionLabel(text: "Pick", color: AppDesign.Colors.warning(for: appColorMode), icon: "arrow.right")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppDesign.Theme.Spacing.xLarge)
                    .padding(.top, AppDesign.Theme.Spacing.hero)
                    
                    Spacer()
                    
                    if let bottom = suggestions.bottom {
                        Button {
                            onCategorize(bottom)
                        } label: {
                            SwipeOptionLabel(text: bottom.name, color: AppDesign.Colors.success(for: appColorMode), icon: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, AppDesign.Theme.Spacing.emptyState)
                    }
                }
                .zIndex(0)
                
                // Card
                VStack(spacing: AppDesign.Theme.Spacing.tight) {
                    Text(displayTitle(for: transaction))
                        .appTitle1Text()
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)

                    Text(transaction.amount, format: .currency(code: currencyCode))
                        .appDisplayText(AppDesign.Theme.DisplaySize.xxxLarge, weight: .heavy)
                        .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(transaction.date, format: .dateTime.month().day().year())
                        .font(AppDesign.Theme.Typography.body)
                        .foregroundStyle(.secondary)
                }
                .padding(AppDesign.Theme.Spacing.screenHorizontal)
                .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.45) // smaller card
                .background(Color(.systemBackground))
                .cornerRadius(AppDesign.Theme.Radius.large)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.large)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 5)
                .offset(offset)
                .rotationEffect(.degrees(Double(offset.width / 20)))
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            offset = gesture.translation
                        }
                        .onEnded { gesture in
                            handleSwipe(translation: gesture.translation)
                        }
                )
                .zIndex(1) // Middle layer
            }
        }
        .onAppear {
            calculateSuggestions()
            refreshTransferCounterparty()
        }
        .onChange(of: transaction) { _, _ in
             offset = .zero
             calculateSuggestions()
             refreshTransferCounterparty()
        }
    }
    
    private func handleSwipe(translation: CGSize) {
        let threshold: CGFloat = 100
        
        if translation.height < -threshold, let topCategory = suggestions.top {
            // Swipe Up
            withAnimation {
                offset.height = -1000
            }
            onCategorize(topCategory)
        } else if translation.height > threshold, let bottomCategory = suggestions.bottom {
            withAnimation {
                offset.height = 1000
            }
            onCategorize(bottomCategory)
        } else if translation.width < -threshold {
            // Skip
            withAnimation {
                offset.width = -500
            }
            onSkip()
        } else if translation.width > threshold {
            // Manual category picker
            withAnimation(.spring()) {
                offset = .zero
            }
            onManual()
        } else {
            // Reset
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }
    
    @MainActor
    private func calculateSuggestions() {
        let payeeLower = transaction.payee.lowercased()
        guard !payeeLower.isEmpty else {
            suggestions = (nil, nil)
            return
        }

        let txMonthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: transaction.date)
        ) ?? transaction.date

        let eligibleCategories = categoryGroups
            .filter { $0.type != .transfer }
            .flatMap { $0.categories ?? [] }
            .filter { $0.isActive(inMonthStart: txMonthStart) }

        // Try ML-based prediction first
        let predictor = CategoryPredictor(modelContext: modelContext)
        if let mlPrediction = predictor.predictCategory(for: transaction),
           mlPrediction.confidence > 0.6,
           eligibleCategories.contains(where: { $0.persistentModelID == mlPrediction.category.persistentModelID }) {
            // Use ML prediction as primary suggestion
            suggestions = (nil, mlPrediction.category)
            return
        }

        // Fall back to legacy payee-based suggestion
        let standardKind = TransactionKind.standard.rawValue
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.kindRawValue == standardKind &&
                t.category != nil
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 2000

        let recentCategorized = (try? modelContext.fetch(descriptor)) ?? []
        let matches = recentCategorized.filter { transaction in
            transaction.payee.lowercased().contains(payeeLower) &&
            transaction.category?.group?.type != .transfer
        }

        var counts: [PersistentIdentifier: Int] = [:]
        for match in matches {
            if let categoryID = match.category?.persistentModelID {
                counts[categoryID, default: 0] += 1
            }
        }

        let sorted = counts.sorted { $0.value > $1.value }

        var top: Category? = nil
        var bottom: Category? = nil

        if let first = sorted.first {
            bottom = eligibleCategories.first { $0.persistentModelID == first.key }
        }

        if sorted.count > 1 {
            top = eligibleCategories.first { $0.persistentModelID == sorted[1].key }
        }

        suggestions = (top, bottom)
    }
    
    private func triggerSkip() {
        withAnimation {
            offset = CGSize(width: -500, height: 0)
        }
        onSkip()
    }

    private func displayTitle(for transaction: Transaction) -> String {
        return transaction.payee
    }

    @MainActor
    private func refreshTransferCounterparty() {
        transferCounterpartyName = nil
        guard transaction.isTransfer, let transferID = transaction.transferID else { return }

        let id: UUID? = transferID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        let other = matches.first { $0.persistentModelID != transaction.persistentModelID }
        transferCounterpartyName = other?.account?.name
    }
}

// Reusable Label Component for Consistency
struct SwipeOptionLabel: View {
    let text: String
    let color: Color
    let icon: String // System image name
    
    var body: some View {
        VStack(spacing: AppDesign.Theme.Spacing.micro) {
            Image(systemName: icon)
                .appTitleText()
                .fontWeight(.bold)
            Text(text)
                .appSecondaryBodyText()
                .fontWeight(.bold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.vertical, AppDesign.Theme.Spacing.small)
        .padding(.horizontal, AppDesign.Theme.Spacing.medium)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.card, style: .continuous))
        .shadow(radius: 4)
        .frame(maxWidth: 120) // Constrain width so it doesn't takeover
    }
}

struct QuickCategorizeSessionView: View {
    @Binding var transactions: [Transaction]
    @Query private var categoryGroups: [CategoryGroup]
    @Query(sort: \SavingsGoal.createdDate, order: .reverse) private var savingsGoals: [SavingsGoal]
        
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    
    @State private var currentIndex = 0
    @State private var showingManualPicker = false
    @State private var showingNewCategorySheet = false
    @State private var newCategoryInitialGroup: CategoryGroup?
    @State private var newCategoryCreatedAtMonthStart: Date?
    @State private var showingTransferMatchPicker = false
    @State private var sortedTransactions: [Transaction] = []
    @State private var transferBaseTransaction: Transaction?
    @State private var undoStack: [UndoAction] = []

    private enum UndoAction {
        case categorized(transactionID: PersistentIdentifier, previousCategoryID: PersistentIdentifier?, removedIndex: Int)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                if currentIndex < sortedTransactions.count {
                    QuickCategorizeView(
                        transaction: sortedTransactions[currentIndex],
                        currencyCode: settings.currencyCode,
                        categoryGroups: categoryGroups,
                        onCategorize: { category in
                            categorizeAndNext(category)
                        },
                        onSkip: {
                            skipAndNext()
                        },
                        onManual: {
                            showingManualPicker = true
                        }
                    )
                } else {
                    VStack {
                        Image(systemName: "checkmark.seal.fill")
                            .appIconHero()
                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                            .padding()
                        Text("All Done!")
                            .appTitleText()
                            .fontWeight(.bold)
                        Button("Finish") {
                            dismiss()
                        }
                        .appPrimaryCTA()
                        .padding()
                    }
                }
            }
            .navigationTitle("Quick Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        undoLastAction()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                }
            }
            .sheet(isPresented: $showingManualPicker) {
                NavigationStack {
                    List {
                        let activeMonthStart: Date? = {
                            guard currentIndex < sortedTransactions.count else { return nil }
                            let date = sortedTransactions[currentIndex].date
                            return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
                        }()
                        let currentSelectedCategoryID = (currentIndex < sortedTransactions.count)
                            ? sortedTransactions[currentIndex].category?.persistentModelID
                            : nil

                        ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                            Section(header: Text(group.name)) {
                                let candidates = group.sortedCategories.filter { category in
                                    guard let activeMonthStart else { return true }
                                    return category.isActive(inMonthStart: activeMonthStart)
                                        || category.persistentModelID == currentSelectedCategoryID
                                }

                                ForEach(candidates) { category in
                                    Button {
                                        categorizeAndNext(category)
                                        showingManualPicker = false
                                    } label: {
                                        let isInactive: Bool = {
                                            guard let activeMonthStart else { return false }
                                            return !category.isActive(inMonthStart: activeMonthStart)
                                        }()
                                        Text(isInactive ? "\(category.name) (Archived)" : category.name)
                                    }
                                }
                            }
                        }

                        let savingsGoalCandidates = savingsGoals.filter { goal in
                            guard let activeMonthStart else { return true }
                            guard let category = goal.category else { return true }
                            return category.isActive(inMonthStart: activeMonthStart)
                                || category.persistentModelID == currentSelectedCategoryID
                        }

                        if !savingsGoalCandidates.isEmpty {
                            Section("Savings Goals") {
                                ForEach(savingsGoalCandidates) { goal in
                                    Button {
                                        let monthStart = activeMonthStart ?? Date()
                                        let category = ensureEnvelopeCategory(for: goal, monthStart: monthStart)
                                        categorizeAndNext(category)
                                        showingManualPicker = false
                                    } label: {
                                        Text(goal.name)
                                    }
                                }
                            }
                        }

                        Section {
                            Button {
                                beginTransferMatch()
                                showingManualPicker = false
                            } label: {
                                Label("Transfer", systemImage: "arrow.left.arrow.right")
                                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                            }
                            .disabled(currentIndex >= sortedTransactions.count)

                            Button {
                                ignoreCurrentTransaction()
                                showingManualPicker = false
                            } label: {
                                Label("Ignore Transaction", systemImage: "nosign")
                                    .foregroundStyle(.secondary)
                            }
                            .disabled(currentIndex >= sortedTransactions.count)
                        }

                        Section {
                            Button {
                                newCategoryInitialGroup = categoryGroups.first(where: { $0.type != .transfer })
                                if currentIndex < sortedTransactions.count {
                                    let date = sortedTransactions[currentIndex].date
                                    newCategoryCreatedAtMonthStart = Calendar.current.date(
                                        from: Calendar.current.dateComponents([.year, .month], from: date)
                                    ) ?? date
                                }
                                showingNewCategorySheet = true
                            } label: {
                                Label("Create New Category", systemImage: "plus.circle")
                            }
                        }
                    }
                    .navigationTitle("Select Category")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { 
                                showingManualPicker = false
                                // Do not advance index
                            }
                        }
                    }
                    .sheet(isPresented: $showingNewCategorySheet, onDismiss: {
                        newCategoryInitialGroup = nil
                        newCategoryCreatedAtMonthStart = nil
                    }) {
                        NewBudgetCategorySheet(
                            initialGroup: newCategoryInitialGroup,
                            createdAtMonthStart: newCategoryCreatedAtMonthStart
                        ) { _ in
                            newCategoryInitialGroup = nil
                            newCategoryCreatedAtMonthStart = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showingTransferMatchPicker) {
                NavigationStack {
                    if let base = transferBaseTransaction {
                        TransferMatchPickerView(
                            base: base,
                            currencyCode: settings.currencyCode,
                            onLinked: { candidate in
                                removeFromSession(base)
                                removeFromSession(candidate)
                            },
                            onMarkedUnmatched: {
                                removeFromSession(base)
                            }
                        )
                    }
                }
            }
            .onAppear {
                // Sort Newest -> Oldest
                sortedTransactions = transactions.sorted { $0.date > $1.date }
            }
        }
    }
    
    private func categorizeAndNext(_ category: Category) {
        let tx = sortedTransactions[currentIndex]
        let old = TransactionSnapshot(from: tx)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)
        let previousCategory = tx.category
        let previousCategoryID = previousCategory?.persistentModelID
        let removedIndex = currentIndex
        undoStack.append(.categorized(
            transactionID: tx.persistentModelID,
            previousCategoryID: previousCategoryID,
            removedIndex: removedIndex
        ))
        tx.kind = .standard
        tx.transferID = nil
        tx.transferInboxDismissed = false
        tx.category = category

        TransactionStatsUpdateCoordinator.markDirty(transaction: tx)
        
        guard modelContext.safeSave(context: "QuickCategorizeView.categorizeAndNext") else {
            tx.category = previousCategory
            _ = undoStack.popLast()
            return
        }

        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: Date(),
            saveContext: "QuickCategorizeView.categorizeAndNext.syncSavingsGoals"
        )
        
        removeFromSession(tx)
    }
    
    private func skipAndNext() {
        withAnimation {
            currentIndex += 1
        }
    }

    private func beginTransferMatch() {
        guard currentIndex < sortedTransactions.count else { return }
        let transaction = sortedTransactions[currentIndex]

        // Convert standard transaction to transfer
        if transaction.kind == .standard {
            let old = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

            transaction.kind = .transfer
            transaction.category = nil
            transaction.transferID = nil
            transaction.transferInboxDismissed = false

            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

            guard modelContext.safeSave(context: "QuickCategorizeView.beginTransferMatch") else {
                return
            }
        }

        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: Date(),
            saveContext: "QuickCategorizeView.beginTransferMatch.syncSavingsGoals"
        )

        transferBaseTransaction = transaction
        showingTransferMatchPicker = true
    }

    private func ignoreCurrentTransaction() {
        guard currentIndex < sortedTransactions.count else { return }
        let transaction = sortedTransactions[currentIndex]

        let old = TransactionSnapshot(from: transaction)
        TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

        transaction.kind = .ignored
        transaction.category = nil
        transaction.transferID = nil
        transaction.transferInboxDismissed = false

        TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

        guard modelContext.safeSave(context: "QuickCategorizeView.ignoreCurrentTransaction") else {
            return
        }

        SavingsGoalEnvelopeSyncService.syncCurrentBalances(
            modelContext: modelContext,
            referenceDate: Date(),
            saveContext: "QuickCategorizeView.ignoreCurrentTransaction.syncSavingsGoals"
        )

        removeFromSession(transaction)
    }

    private func removeFromSession(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        sortedTransactions.removeAll { $0.id == transaction.id }
        if currentIndex >= sortedTransactions.count {
            currentIndex = max(0, sortedTransactions.count - 1)
        }
    }

    @MainActor
    private func undoLastAction() {
        guard let last = undoStack.popLast() else { return }

        switch last {
        case .categorized(let transactionID, let previousCategoryID, let removedIndex):
            guard let tx = modelContext.model(for: transactionID) as? Transaction else { return }

            let old = TransactionSnapshot(from: tx)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)

            let currentCategory = tx.category
            let previousCategory: Category? = {
                guard let previousCategoryID else { return nil }
                return modelContext.model(for: previousCategoryID) as? Category
            }()

            tx.category = previousCategory
            TransactionStatsUpdateCoordinator.markDirty(transaction: tx)
            guard modelContext.safeSave(context: "QuickCategorizeView.undoLastAction") else {
                tx.category = currentCategory
                undoStack.append(last)
                return
            }

            SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                modelContext: modelContext,
                referenceDate: Date(),
                saveContext: "QuickCategorizeView.undoLastAction.syncSavingsGoals"
            )

            if !sortedTransactions.contains(where: { $0.persistentModelID == tx.persistentModelID }) {
                let insertIndex = max(0, min(removedIndex, sortedTransactions.count))
                sortedTransactions.insert(tx, at: insertIndex)
                currentIndex = insertIndex
            }

            if !transactions.contains(where: { $0.persistentModelID == tx.persistentModelID }) {
                transactions.insert(tx, at: 0)
            }
        }
    }

    @discardableResult
    private func ensureEnvelopeCategory(for goal: SavingsGoal, monthStart: Date) -> Category {
        let normalizedMonthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: monthStart)
        ) ?? monthStart

        if let existing = goal.category {
            existing.budgetType = .monthlyRollover
            existing.overspendHandling = .carryNegative
            return existing
        }

        let expenseGroup: CategoryGroup = {
            if let existing = categoryGroups.first(where: { $0.type == .expense && $0.name == "Savings Goals" }) {
                return existing
            }
            let nextOrder = (categoryGroups.map(\.order).max() ?? -1) + 1
            let group = CategoryGroup(name: "Savings Goals", order: nextOrder, type: .expense, isDemoData: goal.isDemoData)
            modelContext.insert(group)
            return group
        }()

        let nextOrder = ((expenseGroup.categories ?? []).map(\.order).max() ?? -1) + 1
        let category = Category(
            name: goal.name,
            assigned: goal.monthlyContribution ?? 0,
            activity: 0,
            order: nextOrder,
            icon: "🎯",
            memo: "Savings goal envelope",
            isDemoData: goal.isDemoData
        )
        category.group = expenseGroup
        category.budgetType = .monthlyRollover
        category.overspendHandling = .carryNegative
        category.createdAt = normalizedMonthStart
        category.savingsGoal = goal
        goal.category = category
        modelContext.insert(category)
        return category
    }
}
