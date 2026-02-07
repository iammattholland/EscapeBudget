import SwiftUI
import SwiftData

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
    @Query(sort: \SavingsGoal.createdDate, order: .reverse) private var savingsGoals: [SavingsGoal]
    @Query(
        filter: #Predicate<Transaction> { tx in
            tx.kindRawValue == "Standard"
        },
        sort: [SortDescriptor(\Transaction.date, order: .reverse)]
    ) private var standardTransactions: [Transaction]
    @Query(sort: \MonthlyCategoryBudget.monthStart, order: .reverse) private var monthlyCategoryBudgets: [MonthlyCategoryBudget]
        @Environment(\.appColorMode) private var appColorMode
        @Environment(\.appSettings) private var settings

    @State private var showingAddGoal = false
    @State private var showingQuickContribute = false
    @State private var selectedGoalForContribution: SavingsGoal?
    @State private var contributionAmount = ""
    @State private var budgetCalculator = CategoryBudgetCalculator(transactions: [], monthlyBudgets: [])
    private let topChrome: AnyView?
    private struct EnvelopeSyncTaskID: Equatable {
        let goalsCount: Int
        let transactionCount: Int
        let budgetsCount: Int
        let token: Int
    }

    init(topChrome: (() -> AnyView)? = nil) {
        self.topChrome = topChrome?()
    }
    
    var body: some View {
        Group {
            if savingsGoals.isEmpty {
                List {
                    if topChrome != nil {
                        AppChromeListRow(topChrome: topChrome, scrollID: "SavingsGoalsView.scroll")
                    }

                EmptyDataCard(
                    systemImage: "target",
                    title: "No Savings Goals",
                    message: "Create a savings goal to start tracking your progress.",
                    actionTitle: "Add Goal",
                    action: { showingAddGoal = true }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .scrollContentBackground(.hidden)
                .appLightModePageBackground()
                .coordinateSpace(name: "SavingsGoalsView.scroll")
            } else {
                List {
                    if topChrome != nil {
                        AppChromeListRow(topChrome: topChrome, scrollID: "SavingsGoalsView.scroll")
                    }

                    // Summary Card
                    Section {
                        VStack(spacing: AppDesign.Theme.Spacing.tight) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Total Saved")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalSaved, format: .currency(code: settings.currencyCode))
                                        .appTitleText()
                                        .fontWeight(.bold)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.micro) {
                                    Text("Total Goal")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalTarget, format: .currency(code: settings.currencyCode))
                                        .appTitleText()
                                }
                            }
                            
                            ProgressView(value: overallProgress)
                                .tint(AppDesign.Colors.tint(for: appColorMode))
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.compact)
                    }
                    
                    // Goals List
                    Section {
                        ForEach(savingsGoals) { goal in
                            SavingsGoalRow(goal: goal)
                                .swipeActions(edge: .leading) {
                                    if !goal.isAchieved {
                                        Button {
                                            selectedGoalForContribution = goal
                                            showingQuickContribute = true
                                        } label: {
                                            Label("Add Money", systemImage: "plus.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteGoal(goal)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .coordinateSpace(name: "SavingsGoalsView.scroll")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingAddGoal = true
                    } label: {
                        Label("Add Goal", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis").appEllipsisIcon()
                }
                .tint(.primary)
                .accessibilityLabel("Savings Goals Menu")
                .accessibilityIdentifier("savingsGoals.menu")
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddSavingsGoalView()
        }
        .alert("Add to \(selectedGoalForContribution?.name ?? "Goal")", isPresented: $showingQuickContribute) {
            TextField("Amount", text: $contributionAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
                contributionAmount = ""
            }
            Button("Add") {
                addContribution()
            }
        } message: {
            Text("How much would you like to assign this month?")
        }
        .task(id: envelopeSyncTaskID) {
            syncEnvelopeState()
        }
    }

    private var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var envelopeSyncTaskID: EnvelopeSyncTaskID {
        EnvelopeSyncTaskID(
            goalsCount: savingsGoals.count,
            transactionCount: standardTransactions.count,
            budgetsCount: monthlyCategoryBudgets.count,
            token: DataChangeTracker.token
        )
    }
    
    private var totalSaved: Decimal {
        savingsGoals.reduce(0) { $0 + $1.currentAmount }
    }
    
    private var totalTarget: Decimal {
        savingsGoals.reduce(0) { $0 + $1.targetAmount }
    }
    
    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return Double(truncating: (totalSaved / totalTarget) as NSNumber)
    }
    
    private func deleteGoal(_ goal: SavingsGoal) {
        if let category = goal.category {
            let categoryID = category.persistentModelID
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.category?.persistentModelID == categoryID
                }
            )
            descriptor.fetchLimit = 1
            let hasTransactions = !(((try? modelContext.fetch(descriptor)) ?? []).isEmpty)
            if hasTransactions {
                let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
                category.archivedAfterMonthStart = cutoff
            } else {
                modelContext.delete(category)
            }
        }
        modelContext.delete(goal)
        modelContext.safeSave(context: "SavingsGoalsView.deleteGoal")
    }

    private func addContribution() {
        guard let goal = selectedGoalForContribution,
              let amount = Decimal(string: contributionAmount),
              amount > 0 else {
            contributionAmount = ""
            return
        }

        let category = ensureEnvelopeCategory(for: goal)
        let categoryID = category.persistentModelID
        var descriptor = FetchDescriptor<MonthlyCategoryBudget>(
            predicate: #Predicate<MonthlyCategoryBudget> { entry in
                entry.category?.persistentModelID == categoryID &&
                entry.monthStart == currentMonthStart
            }
        )
        descriptor.fetchLimit = 1
        let existing = (try? modelContext.fetch(descriptor))?.first
        let baseline = existing?.amount ?? category.assigned
        let updatedAmount = baseline + amount
        if let existing {
            existing.amount = updatedAmount
        } else if updatedAmount != category.assigned {
            modelContext.insert(
                MonthlyCategoryBudget(
                    monthStart: currentMonthStart,
                    amount: updatedAmount,
                    category: category,
                    isDemoData: goal.isDemoData
                )
            )
        }

        contributionAmount = ""
        selectedGoalForContribution = nil

        syncEnvelopeState()
    }

    @discardableResult
    private func ensureEnvelopeCategory(for goal: SavingsGoal) -> Category {
        if let existing = goal.category {
            existing.budgetType = .monthlyRollover
            existing.overspendHandling = .carryNegative
            if let monthlyContribution = goal.monthlyContribution, monthlyContribution >= 0 {
                existing.assigned = monthlyContribution
            }
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
        category.createdAt = currentMonthStart
        category.savingsGoal = goal
        goal.category = category
        modelContext.insert(category)
        return category
    }

    private func syncEnvelopeState() {
        budgetCalculator = CategoryBudgetCalculator(
            transactions: standardTransactions,
            monthlyBudgets: monthlyCategoryBudgets
        )

        var changed = false
        for goal in savingsGoals {
            let category = ensureEnvelopeCategory(for: goal)
            let summary = budgetCalculator.monthSummary(for: category, monthStart: currentMonthStart)
            let envelopeBalance = max(Decimal.zero, summary.endingAvailable)
            if goal.currentAmount != envelopeBalance {
                goal.currentAmount = envelopeBalance
                changed = true
            }

            if category.name != goal.name {
                category.name = goal.name
                changed = true
            }

            if let monthlyContribution = goal.monthlyContribution, monthlyContribution >= 0, category.assigned != monthlyContribution {
                category.assigned = monthlyContribution
                changed = true
            }
        }

        if changed {
            modelContext.safeSave(context: "SavingsGoalsView.syncEnvelopeState")
        }
    }
}

// MARK: - Savings Goal Row

struct SavingsGoalRow: View {
    let goal: SavingsGoal
        @Environment(\.appColorMode) private var appColorMode
        @Environment(\.appSettings) private var settings

    private var color: Color {
        Color(hex: goal.colorHex) ?? AppDesign.Colors.tint(for: appColorMode)
    }

    private var smartInsight: String? {
        if goal.isAchieved {
            return "🎉 Goal achieved!"
        }

        let remaining = goal.amountRemaining

        // Show how close they are
        if remaining <= 50 {
            return "Almost there! Just \(remaining.formatted(.currency(code: settings.currencyCode))) to go"
        }

        // Show timeline projection based on monthly contribution
        if let monthly = goal.monthlyContribution, monthly > 0 {
            let monthsRemaining = Int(ceil(Double(truncating: (remaining / monthly) as NSNumber)))
            if monthsRemaining == 1 {
                return "One more month at current pace"
            } else if monthsRemaining <= 12 {
                return "\(monthsRemaining) months at current pace"
            }
        }

        // Show days until target date
        if let targetDate = goal.targetDate {
            let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
            if daysUntil > 0 && daysUntil <= 7 {
                return "\(daysUntil) day\(daysUntil == 1 ? "" : "s") until target"
            } else if daysUntil > 7 && daysUntil <= 30 {
                let weeks = daysUntil / 7
                return "\(weeks) week\(weeks == 1 ? "" : "s") until target"
            }
        }

        return nil
    }

    var body: some View {
        NavigationLink(destination: SavingsGoalDetailView(goal: goal)) {
            HStack(spacing: AppDesign.Theme.Spacing.medium) {
                // Circular Progress Ring (simplified)
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: min(goal.progressPercentage / 100, 1.0))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    if goal.isAchieved {
                        Image(systemName: "checkmark")
                            .appTitleText()
                            .foregroundStyle(color)
                    } else {
                        Text("\(Int(goal.progressPercentage))%")
                            .appCaptionText()
                            .fontWeight(.bold)
                            .foregroundStyle(color)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text(goal.name)
                        .appSectionTitleText()

                    Text("\(goal.currentAmount, format: .currency(code: settings.currencyCode)) of \(goal.targetAmount, format: .currency(code: settings.currencyCode))")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)

                    if let insight = smartInsight {
                        Text(insight)
                            .appCaptionText()
                            .foregroundStyle(goal.isAchieved ? AppDesign.Colors.success(for: appColorMode) : color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppDesign.Theme.Spacing.compact)
        }
    }
}

// MARK: - Add/Edit View

struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [SavingsGoal]
        @Environment(\.appColorMode) private var appColorMode
    
    @State private var name = ""
    @State private var targetAmount = ""
    @State private var currentAmount = ""
    @State private var useTargetDate = true
    @State private var targetDate = Date().addingTimeInterval(86400 * 365) // 1 year from now
    @State private var monthlyContribution = ""
    @State private var selectedColorHex = "007AFF"
    @State private var notes = ""

    private var colorOptions: [(hex: String, name: String)] {
        switch appColorMode {
        case .standard:
            return [
                ("007AFF", "Blue"),
                ("FF9500", "Orange"),
                ("FF2D55", "Pink"),
                ("5AC8FA", "Teal"),
                ("34C759", "Green"),
                ("AF52DE", "Purple")
            ]
        case .neutral:
            return [
                ("576980", "Slate"),
                ("5C806B", "Sage"),
                ("9E8057", "Sand"),
                ("9E5C66", "Rose"),
                ("7C5C8A", "Plum"),
                ("6B7280", "Graphite")
            ]
        }
    }

    private var defaultColorHex: String {
        colorOptions.first?.hex ?? "007AFF"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal Name", text: $name)
                    TextField("Target Amount", text: $targetAmount)
                        .keyboardType(.decimalPad)
                    TextField("Current Amount", text: $currentAmount)
                        .keyboardType(.decimalPad)
                }
                
                Section("Timeframe") {
                    Picker("Method", selection: $useTargetDate) {
                        Text("Target Date").tag(true)
                        Text("Monthly Amount").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if useTargetDate {
                        DatePicker("Target Date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    } else {
                        TextField("Monthly Contribution", text: $monthlyContribution)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: AppDesign.Theme.Spacing.tight) {
                        ForEach(colorOptions, id: \.0) { hex, name in
                            Circle()
                                .fill(Color(hex: hex) ?? AppDesign.Colors.tint(for: appColorMode))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColorHex == hex ? Color.primary : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    selectedColorHex = hex
                                }
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .onAppear {
                if selectedColorHex == "007AFF" {
                    selectedColorHex = defaultColorHex
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(name.isEmpty || targetAmount.isEmpty)
                }
            }
        }
    }
    
    private func saveGoal() {
        let target = Decimal(string: targetAmount) ?? 0
        let current = Decimal(string: currentAmount) ?? 0
        let monthly = useTargetDate ? nil : (Decimal(string: monthlyContribution) ?? 0)
        let date = useTargetDate ? targetDate : nil
        
        let goal = SavingsGoal(
            name: name,
            targetAmount: target,
            currentAmount: current,
            targetDate: date,
            monthlyContribution: monthly,
            colorHex: selectedColorHex,
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(goal)
        dismiss()
    }
}

// MARK: - Detail View

struct SavingsGoalDetailView: View {
    let goal: SavingsGoal
        @Environment(\.appColorMode) private var appColorMode
        @Environment(\.appSettings) private var settings
    
    var body: some View {
        List {
            Section {
                VStack(spacing: AppDesign.Theme.Spacing.medium) {
                    Text(goal.progressPercentage, format: .percent.precision(.fractionLength(1)))
                        .appDisplayText(AppDesign.Theme.DisplaySize.hero, weight: .bold)
                        .foregroundStyle(Color(hex: goal.colorHex) ?? AppDesign.Colors.tint(for: appColorMode))
                    
                    ProgressView(value: goal.progressPercentage / 100)
                        .tint(Color(hex: goal.colorHex) ?? AppDesign.Colors.tint(for: appColorMode))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppDesign.Theme.Spacing.compact)
            }
            
            Section("Progress") {
                LabeledContent("Current Amount", value: goal.currentAmount, format: .currency(code: settings.currencyCode))
                LabeledContent("Target Amount", value: goal.targetAmount, format: .currency(code: settings.currencyCode))
                LabeledContent("Remaining", value: goal.amountRemaining, format: .currency(code: settings.currencyCode))
            }
            
            if let targetDate = goal.targetDate {
                Section("Timeline") {
                    LabeledContent("Target Date", value: targetDate, format: .dateTime.day().month().year())
                    if let suggested = goal.calculatedMonthlyContribution {
                        LabeledContent("Suggested Monthly", value: suggested, format: .currency(code: settings.currencyCode))
                    }
                }
            } else if let monthly = goal.monthlyContribution {
                Section("Timeline") {
                    LabeledContent("Monthly Contribution", value: monthly, format: .currency(code: settings.currencyCode))
                    if let completionDate = goal.calculatedCompletionDate {
                        LabeledContent("Expected Completion", value: completionDate, format: .dateTime.day().month().year())
                    }
                }
            }
            
            if let notes = goal.notes {
                Section("Notes") {
                    Text(notes)
                        .font(AppDesign.Theme.Typography.body)
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SavingsGoalsView()
        .modelContainer(for: [SavingsGoal.self], inMemory: true)
}
