import SwiftUI
import SwiftData

struct ManageView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @State private var transactionsSearchText = ""
    @State private var budgetSearchText = ""
    @State private var accountsSearchText = ""
    @State private var filter = TransactionFilter()

    private var activeSearchText: Binding<String> {
        switch navigator.manageSelectedSection {
        case .transactions:
            return $transactionsSearchText
        case .budget:
            return $budgetSearchText
        case .accounts:
            return $accountsSearchText
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Section", selection: $navigator.manageSelectedSection) {
                    ForEach(ManageSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                CompactSearchBar(text: activeSearchText, placeholder: "Search")
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                // Content
                Group {
                    switch navigator.manageSelectedSection {
                    case .transactions:
                        AllTransactionsView(searchText: $transactionsSearchText, filter: $filter)
                    case .budget:
                        ManageBudgetView(searchText: $budgetSearchText)
                    case .accounts:
                        AccountsView(searchText: $accountsSearchText)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .globalKeyboardDoneToolbar()
            .withAppLogo()
            .foregroundColor(.primary)
            .sheet(isPresented: $navigator.showingAddTransaction) {
                TransactionFormView()
            }
        }
    }
    
    private var navigationTitle: String {
        switch navigator.manageSelectedSection {
        case .transactions:
            return "Manage"
        case .budget:
            return "Manage Budget"
        case .accounts:
            return "Manage Accounts"
        }
    }

}

struct ManageBudgetView: View {
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]
    @Binding var searchText: String
    @State private var showingBudgetSetup = false

    private var hasBudget: Bool {
        categoryGroups.contains { $0.type == .expense }
    }

    var body: some View {
        Group {
            if hasBudget {
                BudgetView(searchText: $searchText)
            } else {
                List {
                    EmptyDataCard(
                        systemImage: "chart.pie.fill",
                        title: "No Budget Yet",
                        message: "Set up your budget to start planning and tracking spending.",
                        actionTitle: "Set Up Budget",
                        action: { showingBudgetSetup = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $showingBudgetSetup) {
            BudgetSetupWizardView(replaceExistingDefault: false)
        }
    }
}

// MARK: - Manage Budget UI Components

private struct ManageBudgetHeroCard: View {
    @Binding var selectedDate: Date
    let totalAssigned: Decimal
    let totalSpent: Decimal
    let totalRemaining: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MonthNavigationHeader(selectedDate: $selectedDate)

            HStack(spacing: 12) {
                ManageBudgetMetric(title: "Budgeted", value: totalAssigned, currencyCode: currencyCode, tint: .primary)
                ManageBudgetMetric(title: "Spent", value: totalSpent, currencyCode: currencyCode, tint: .secondary)
                ManageBudgetMetric(title: "Left", value: totalRemaining, currencyCode: currencyCode, tint: totalRemaining >= 0 ? .secondary : AppColors.danger(for: appColorMode))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ManageBudgetMetric: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct ManageBudgetInsightsCard: View {
    let needsBudgetCount: Int
    let coverage: Double?
    let monthTransactions: Int
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Health")
                .font(.headline)

            HStack(spacing: 12) {
                InsightPill(
                    title: "Needs Budget",
                    detail: needsBudgetCount == 0 ? "All set" : "\(needsBudgetCount) categories",
                    icon: "exclamationmark.triangle.fill",
                    tint: needsBudgetCount == 0 ? AppColors.success(for: appColorMode) : AppColors.warning(for: appColorMode)
                )

                InsightPill(
                    title: "Coverage",
                    detail: coverageText,
                    icon: "shield.lefthalf.filled",
                    tint: AppColors.tint(for: appColorMode)
                )

                InsightPill(
                    title: "Tracked",
                    detail: "\(monthTransactions) tx",
                    icon: "list.number",
                    tint: .purple
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var coverageText: String {
        guard let coverage else { return "—" }
        return "\(Int(coverage * 100))% of plan"
    }
}

private struct InsightPill: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(tint)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct BudgetQuickActionsRow: View {
    let onAddGroup: () -> Void
    let onAddCategory: () -> Void
    let onGuidedSetup: () -> Void
    let onAdvancedManager: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(title: "Add Group", icon: "folder.badge.plus", tint: AppColors.tint(for: appColorMode), action: onAddGroup)
                QuickActionButton(title: "Add Category", icon: "plus.square.dashed", tint: .purple, action: onAddCategory)
            }

            HStack(spacing: 12) {
                QuickActionButton(title: "Guided Setup", icon: "wand.and.sparkles", tint: AppColors.warning(for: appColorMode), action: onGuidedSetup)
                QuickActionButton(title: "Advanced Editor", icon: "square.and.pencil", tint: .gray, action: onAdvancedManager)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}

private struct BudgetGroupCard: View {
    let group: CategoryGroup
    let categories: [Category]
    let currencyCode: String
    let selectedDate: Date
    let transactions: [Transaction]
    let accentColor: Color
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onSelectCategory: (Category) -> Void
    let onAddCategory: () -> Void

    private var assignedTotal: Decimal {
        categories.reduce(0) { $0 + $1.assigned }
    }

    private var spentTotal: Decimal {
        categories.reduce(0) { $0 + monthlyActivity(for: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            if !isCollapsed {
                VStack(spacing: 10) {
                    ForEach(categories) { category in
                        BudgetCategoryRowView(
                            category: category,
                            selectedDate: selectedDate,
                            transactions: transactions,
                            onTap: { onSelectCategory(category) }
                        )
                        Divider()
                    }

                    Button(action: onAddCategory) {
                        Label("Add category", systemImage: "plus.circle.fill")
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(accentColor)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var summaryText: String {
        let remaining = assignedTotal - spentTotal
        return "\(assignedTotal.formatted(.currency(code: currencyCode))) • \(remaining >= 0 ? "Left" : "Over") \(abs(remaining).formatted(.currency(code: currencyCode)))"
    }

    private func monthlyActivity(for category: Category) -> Decimal {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let catTransactions = transactions.filter {
            $0.category?.persistentModelID == category.persistentModelID &&
            $0.date >= start && $0.date < end
        }
        let net = catTransactions.reduce(Decimal.zero) { $0 + $1.amount }
        if category.group?.type == .income {
            return max(0, net)
        } else {
            return max(0, -net)
        }
    }
}

private struct BudgetEmptyStateCard: View {
    let action: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.tint(for: appColorMode))

            Text("Craft Your Budget")
                .font(.title2)
                .fontWeight(.bold)

            Text("Design groups, set targets, and keep spending aligned with your goals. Guided setup walks you through everything.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text("Set Up Budget")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ManageBudgetHighlightsView: View {
    let highlights: [(String, String, String)] = [
        ("folder.badge.plus", "Build groups", "Organize spending with focused categories."),
        ("slider.horizontal.3", "Set monthly targets", "Tell the app how much to budget for each area."),
        ("wand.and.sparkles", "Use smart presets", "Start fast with curated templates you can customize.")
    ]
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What to expect")
                .font(.headline)

            ForEach(highlights, id: \.0) { highlight in
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.tint(for: appColorMode).opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: highlight.0)
                                .foregroundStyle(AppColors.tint(for: appColorMode))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.1)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(highlight.2)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Guided Setup

struct BudgetSetupWizardView: View {
    enum Step {
        case intro, templates, income, assign, review
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Query(sort: \CategoryGroup.order) private var existingGroups: [CategoryGroup]
    @Environment(\.appColorMode) private var appColorMode

    private let replaceExistingDefault: Bool

    init(replaceExistingDefault: Bool = false) {
        self.replaceExistingDefault = replaceExistingDefault
        _replaceExistingBudget = State(initialValue: replaceExistingDefault)
    }

    @State private var step: Step = .intro
    @State private var templates: [BudgetTemplateGroup] = BudgetTemplateGroup.defaults
    @State private var customTemplates: [BudgetTemplateGroup] = []
    @State private var selectedTemplateIDs: Set<UUID> = []
    @State private var selectedCategoryIDs: [UUID: Set<UUID>] = [:]
    @State private var budgetInputs: [UUID: String] = [:]
    @State private var incomeSources: [String] = ["Paycheck"]
    @State private var showingAddCustomGroup = false
    @State private var editingCustomGroup = EditableCustomGroup()
    @State private var creationError: String?
    @State private var replaceExistingBudget = false
    @State private var showingSuggestedAmounts = false

    private var selectedGroups: [BudgetTemplateGroup] {
        let selectedTemplates: [BudgetTemplateGroup] = templates.compactMap { template in
            guard selectedTemplateIDs.contains(template.id) else { return nil }
            let ids = selectedCategoryIDs[template.id] ?? Set(template.categories.map(\.id))
            let categories = template.categories.filter { ids.contains($0.id) }
            guard !categories.isEmpty else { return nil }
            return BudgetTemplateGroup(id: template.id, name: template.name, categories: categories)
        }
        return selectedTemplates + customTemplates
    }

    private var hasExistingExpenseBudget: Bool {
        existingGroups.contains(where: { $0.type == .expense })
    }

    private var hasExistingIncomeCategories: Bool {
        (existingGroups.first(where: { $0.type == .income })?.sortedCategories.isEmpty == false)
    }

    private var nextButtonTitle: String {
        switch step {
        case .review:
            return "Create Budget"
        case .assign:
            return "Review"
        default:
            return "Next"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                ProgressView(value: progressValue)
                    .tint(AppColors.tint(for: appColorMode))

                switch step {
                case .intro:
                    BudgetSetupIntro()
                case .templates:
                    BudgetTemplateSelectionView(
                        templates: templates,
                        customTemplates: customTemplates,
                        selectedTemplateIDs: $selectedTemplateIDs,
                        selectedCategoryIDs: $selectedCategoryIDs,
                        onAddCustomGroup: { showingAddCustomGroup = true }
                    )
                case .income:
                    BudgetIncomeSourcesView(incomeSources: $incomeSources)
                case .assign:
                    BudgetAssignmentView(
                        groups: selectedGroups,
                        budgetInputs: $budgetInputs,
                        currencyCode: displayCurrencyCode,
                        showingSuggestedAmounts: $showingSuggestedAmounts
                    )
                case .review:
                    BudgetSetupReview(groups: selectedGroups, budgetInputs: budgetInputs, currencyCode: displayCurrencyCode)
                }

                if step == .review, hasExistingExpenseBudget {
                    Toggle(isOn: $replaceExistingBudget) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replace existing budget")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Deletes current expense groups and categories before creating the new plan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppColors.warning(for: appColorMode))
                }

                Spacer()

                HStack {
                    Button("Back") {
                        goBack()
                    }
                    .disabled(step == .intro)

                    Spacer()

                    if step == .templates {
                        Button("Select All") {
                            selectAllBudgetGroups()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    if step == .assign {
                        Button {
                            showingSuggestedAmounts = true
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.headline)
                                Text("Assign Suggested")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.tint(for: appColorMode).opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.tint(for: appColorMode))

                        Spacer()
                    }

                    Button(nextButtonTitle) {
                        goForward()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nextDisabled)
                }
            }
            .padding(24)
            .navigationTitle("Budget Setup")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCustomGroup) {
                CustomGroupEditor(
                    group: editingCustomGroup,
                    onSave: { newGroup in
                        let template = BudgetTemplateGroup(
                            id: UUID(),
                            name: newGroup.name,
                            categories: newGroup.categories.map { BudgetTemplateCategory(id: UUID(), name: $0, suggestedAmount: 0) }
                        )
                        customTemplates.append(template)
                        editingCustomGroup = EditableCustomGroup()
                        showingAddCustomGroup = false
                    },
                    onCancel: {
                        editingCustomGroup = EditableCustomGroup()
                        showingAddCustomGroup = false
                    }
                )
            }
            .alert("Almost there", isPresented: Binding<Bool>(
                get: { creationError != nil },
                set: { _ in creationError = nil }
            )) {
                Button("OK", role: .cancel) { creationError = nil }
            } message: {
                Text(creationError ?? "")
            }
        }
    }

    private var displayCurrencyCode: String { currencyCode }

    private var progressValue: Double {
        switch step {
        case .intro: return 0.1
        case .templates: return 0.3
        case .income: return 0.5
        case .assign: return 0.75
        case .review: return 1.0
        }
    }

    private var nextDisabled: Bool {
        switch step {
        case .templates:
            return selectedGroups.isEmpty
        case .income:
            return false
        case .assign:
            return selectedGroups.isEmpty
        default:
            return false
        }
    }

    private func selectAllBudgetGroups() {
        selectedTemplateIDs = Set(templates.map(\.id))
        for template in templates {
            selectedCategoryIDs[template.id] = Set(template.categories.map(\.id))
        }
    }

    private func goBack() {
        switch step {
        case .intro: break
        case .templates: step = .intro
        case .income: step = .templates
        case .assign: step = .income
        case .review: step = .assign
        }
    }

    private func goForward() {
        switch step {
        case .intro:
            step = .templates
        case .templates:
            guard !nextDisabled else { return }
            seedBudgetInputs()
            step = .income
        case .income:
            step = .assign
        case .assign:
            step = .review
        case .review:
            createBudget()
        }
    }

    private func seedBudgetInputs() {
        for group in selectedGroups {
            for category in group.categories {
                if budgetInputs[category.id] == nil {
                    let suggestion = category.suggestedAmount > 0 ?
                        category.suggestedAmount.formatted(.number.precision(.fractionLength(0))) :
                        ""
                    budgetInputs[category.id] = suggestion
                }
            }
        }
    }

    private func createBudget() {
        guard !selectedGroups.isEmpty else {
            creationError = "Select at least one group to create."
            return
        }

        if replaceExistingBudget {
            // Remove only expense budget groups; keep system groups (Transfer, Income)
            for group in existingGroups where group.type == .expense {
                modelContext.delete(group)
            }
            guard modelContext.safeSave(context: "ManageView.createBudget.deleteExisting", showErrorToUser: false) else {
                creationError = "Couldn’t update your budget. Please try again."
                return
            }
        }

        let startOrder: Int = {
            if replaceExistingBudget { return 0 }
            return (existingGroups.map { $0.order }.max() ?? -1) + 1
        }()

        var currentOrder = startOrder

        withAnimation {
            for group in selectedGroups {
                let newGroup = CategoryGroup(name: group.name, order: currentOrder, type: .expense)
                modelContext.insert(newGroup)

                for (index, category) in group.categories.enumerated() {
                    let customAmount = decimalValue(from: budgetInputs[category.id] ?? "")
                    let categoryModel = Category(
                        name: category.name,
                        assigned: customAmount ?? category.suggestedAmount,
                        activity: 0,
                        order: index
                    )
                    categoryModel.group = newGroup
                    modelContext.insert(categoryModel)
                }

                currentOrder += 1
            }

            upsertIncomeSourcesIfNeeded()
            guard modelContext.safeSave(context: "ManageView.createBudget.save", showErrorToUser: false) else {
                creationError = "Couldn’t create your budget. Please try again."
                return
            }
        }

        dismiss()
    }

    private func upsertIncomeSourcesIfNeeded() {
        let cleaned = incomeSources
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return }

        let incomeGroup: CategoryGroup = {
            if let existing = existingGroups.first(where: { $0.type == .income }) {
                return existing
            }
            let group = CategoryGroup(name: "Income", order: -1, type: .income)
            modelContext.insert(group)
            return group
        }()

        let existingNames = Set((incomeGroup.categories ?? []).map { $0.name.lowercased() })
        var order = (incomeGroup.categories?.map(\.order).max() ?? -1) + 1
        for name in cleaned where !existingNames.contains(name.lowercased()) {
            let category = Category(name: name, assigned: 0, activity: 0, order: order)
            category.group = incomeGroup
            modelContext.insert(category)
            order += 1
        }
    }

    private func decimalValue(from string: String) -> Decimal? {
        let sanitized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: currencySymbol(), with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !sanitized.isEmpty else { return nil }
        return Decimal(string: sanitized)
    }

    private func currencySymbol() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = displayCurrencyCode
        return formatter.currencySymbol ?? "$"
    }
}

private struct BudgetIncomeSourcesView: View {
    @Binding var incomeSources: [String]
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income sources")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add your income categories (optional). They’ll appear under Manage Budget once created.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(incomeSources.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.left.circle.fill")
                            .foregroundStyle(AppColors.success(for: appColorMode))

                        TextField("Eg. Paycheck", text: binding(for: index))
                            .textFieldStyle(.plain)

                        if incomeSources.count > 1 {
                            Button(role: .destructive) {
                                incomeSources.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                }

                Button {
                    incomeSources.append("")
                } label: {
                    Label("Add income source", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { incomeSources[index] },
            set: { incomeSources[index] = $0 }
        )
    }
}

private struct BudgetSetupIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let's build your budget")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("We'll suggest popular groups, let you fine-tune categories, and capture the numbers that matter most.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Label("Curated templates with smart defaults", systemImage: "wand.and.stars")
                Label("Enter your amounts once", systemImage: "rectangle.and.pencil.and.ellipsis")
                Label("Edit or add custom groups anytime", systemImage: "slider.horizontal.3")
            }
            .font(.callout)
        }
    }
}

private struct BudgetTemplateSelectionView: View {
    let templates: [BudgetTemplateGroup]
    let customTemplates: [BudgetTemplateGroup]
    @Binding var selectedTemplateIDs: Set<UUID>
    @Binding var selectedCategoryIDs: [UUID: Set<UUID>]
    let onAddCustomGroup: () -> Void
    @State private var expandedGroupIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose budget groups")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(templates) { template in
                        BudgetTemplateCard(
                            template: template,
                            isSelected: Binding(
                                get: { selectedTemplateIDs.contains(template.id) },
                                set: { newValue in setGroupSelected(template, isSelected: newValue) }
                            ),
                            selectedCategoryIDs: Binding(
                                get: { selectedCategoryIDs[template.id] ?? [] },
                                set: { newValue in
                                    selectedCategoryIDs[template.id] = newValue
                                    if newValue.isEmpty {
                                        selectedTemplateIDs.remove(template.id)
                                        selectedCategoryIDs[template.id] = nil
                                    } else {
                                        selectedTemplateIDs.insert(template.id)
                                    }
                                }
                            ),
                            isExpanded: Binding(
                                get: { expandedGroupIDs.contains(template.id) },
                                set: { newValue in
                                    if newValue { expandedGroupIDs.insert(template.id) }
                                    else { expandedGroupIDs.remove(template.id) }
                                }
                            )
                        )
                    }

                    if !customTemplates.isEmpty {
                        Divider().padding(.vertical, 8)
                        ForEach(customTemplates) { template in
                            BudgetTemplateCard(
                                template: template,
                                isSelected: .constant(true),
                                selectedCategoryIDs: .constant(Set(template.categories.map(\.id))),
                                isExpanded: .constant(false),
                                isCustom: true
                            )
                        }
                    }

                    Button(action: onAddCustomGroup) {
                        Label("Add custom group", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func setGroupSelected(_ template: BudgetTemplateGroup, isSelected: Bool) {
        if isSelected {
            selectedTemplateIDs.insert(template.id)
            selectedCategoryIDs[template.id] = Set(template.categories.map(\.id))
            expandedGroupIDs.insert(template.id)
        } else {
            selectedTemplateIDs.remove(template.id)
            selectedCategoryIDs[template.id] = nil
            expandedGroupIDs.remove(template.id)
        }
    }
}

private struct BudgetTemplateCard: View {
    let template: BudgetTemplateGroup
    @Binding var isSelected: Bool
    @Binding var selectedCategoryIDs: Set<UUID>
    @Binding var isExpanded: Bool
    var isCustom: Bool = false
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name)
                    .font(.headline)
                Spacer()
                if isCustom {
                    Text("Custom")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        isSelected.toggle()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? AppColors.tint(for: appColorMode) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Text("\(selectedCount) of \(template.categories.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !isCustom {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded && !isCustom {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(template.categories) { category in
                        Toggle(isOn: Binding(
                            get: { selectedCategoryIDs.contains(category.id) },
                            set: { newValue in
                                var updated = selectedCategoryIDs
                                if newValue {
                                    updated.insert(category.id)
                                    isSelected = true
                                } else {
                                    updated.remove(category.id)
                                    if updated.isEmpty {
                                        isSelected = false
                                    }
                                }
                                selectedCategoryIDs = updated
                            }
                        )) {
                            Text(category.name)
                                .font(.subheadline)
                        }
                        .tint(AppColors.tint(for: appColorMode))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AppColors.tint(for: appColorMode) : Color.primary.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var selectedCount: Int {
        guard !isCustom else { return template.categories.count }
        guard isSelected else { return 0 }
        if selectedCategoryIDs.isEmpty { return template.categories.count }
        return min(selectedCategoryIDs.count, template.categories.count)
    }
}

private struct BudgetAssignmentView: View {
    let groups: [BudgetTemplateGroup]
    @Binding var budgetInputs: [UUID: String]
    let currencyCode: String
    @Binding var showingSuggestedAmounts: Bool

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? "$"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign monthly amounts")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Budget amounts")
                            .font(.headline)

                        Text("Enter monthly amounts for each category. You can always adjust later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(group.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Spacer()

                                    Text(groupTotal(for: group), format: .currency(code: currencyCode))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(group.categories) { category in
                                    HStack(spacing: 12) {
                                        Text(category.name)
                                            .font(.subheadline)

                                        Spacer()

                                        HStack(spacing: 4) {
                                            Text(currencySymbol)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 8)

                                            TextField(
                                                "0",
                                                text: Binding(
                                                    get: { budgetInputs[category.id, default: ""] },
                                                    set: { budgetInputs[category.id] = $0 }
                                                )
                                            )
                                            .keyboardType(.decimalPad)
                                            .font(.subheadline)
                                            .multilineTextAlignment(.trailing)
                                        }
                                        .frame(width: 100)
                                        .padding(.vertical, 8)
                                        .padding(.trailing, 8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
            }
        }
        .sheet(isPresented: $showingSuggestedAmounts) {
            BudgetSuggestionView(
                groups: groups,
                budgetInputs: $budgetInputs,
                currencyCode: currencyCode
            )
        }
    }

    private func groupTotal(for group: BudgetTemplateGroup) -> Decimal {
        var total: Decimal = 0
        for category in group.categories {
            guard let amountStr = budgetInputs[category.id],
                  let amount = Decimal(string: amountStr.replacingOccurrences(of: ",", with: "")) else {
                continue
            }
            total += amount
        }
        return total
    }
}

private struct BudgetSuggestionView: View {
    let groups: [BudgetTemplateGroup]
    @Binding var budgetInputs: [UUID: String]
    let currencyCode: String

	@Environment(\.dismiss) private var dismiss
	@Environment(\.appColorMode) private var appColorMode
	@State private var monthlyIncomeInput = ""
	@State private var targetSavingsRate = 10.0
	@State private var suggestedAmounts: [UUID: Decimal] = [:]
	@State private var customizedAmounts: [UUID: String] = [:]

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? "$"
    }

    private var monthlyIncome: Decimal {
        guard let income = Decimal(string: monthlyIncomeInput.replacingOccurrences(of: ",", with: "")) else {
            return 0
        }
        return income
    }

    private var totalBudgeted: Decimal {
        var total: Decimal = 0
        for group in groups {
            for category in group.categories {
                if let amountStr = customizedAmounts[category.id],
                   let amount = Decimal(string: amountStr.replacingOccurrences(of: ",", with: "")) {
                    total += amount
                } else if let suggested = suggestedAmounts[category.id] {
                    total += suggested
                }
            }
        }
        return total
    }

    private var savingsAmount: Decimal {
        return monthlyIncome - totalBudgeted
    }

	private var savingsRate: Double {
		guard monthlyIncome > 0 else { return 0 }
		return Double(truncating: (savingsAmount / monthlyIncome) as NSNumber) * 100
	}

	private var targetSavingsAmount: Decimal {
		guard monthlyIncome > 0 else { return 0 }
		return monthlyIncome * Decimal(targetSavingsRate / 100)
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
                    // Income Input Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Monthly Net Income")
                            .font(.headline)

                        Text("Enter your monthly take-home pay after taxes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text(currencySymbol)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)

                            TextField("0", text: $monthlyIncomeInput)
                                .keyboardType(.decimalPad)
                                .font(.body)
                                .onChange(of: monthlyIncomeInput) { _, _ in
                                    calculateSuggestions()
                                }
                        }
                        .padding(.vertical, 14)
                        .padding(.trailing, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )

                    // Summary Card
                    if monthlyIncome > 0 {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Budget Summary")
                                .font(.headline)

                            HStack(spacing: 12) {
                                SummaryMetric(
                                    title: "Total Budget",
                                    value: totalBudgeted,
                                    currencyCode: currencyCode,
                                    tint: .primary
                                )

                                SummaryMetric(
                                    title: "Savings",
                                    value: savingsAmount,
                                    currencyCode: currencyCode,
                                    tint: savingsAmount >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode)
                                )
                            }

	                            VStack(alignment: .leading, spacing: 10) {
	                                HStack {
	                                    Text("Savings Rate")
	                                        .font(.subheadline)
	                                        .fontWeight(.semibold)
	                                    Spacer()
	                                    Text("\(Int(targetSavingsRate))%")
	                                        .font(.title3)
	                                        .fontWeight(.bold)
	                                        .foregroundStyle(savingsRateColor)
	                                }

	                                Slider(value: $targetSavingsRate, in: 0...50, step: 1)
	                                    .tint(savingsRateColor)
	                                    .onChange(of: targetSavingsRate) { _, _ in
	                                        calculateSuggestions()
	                                    }

	                                HStack {
	                                    Text("Target: \(targetSavingsAmount, format: .currency(code: currencyCode))")
	                                    Spacer()
	                                    Text("Actual: \(Int(savingsRate))%")
	                                }
	                                .font(.caption)
	                                .foregroundStyle(.secondary)

	                                ProgressView(value: max(0, min(1, savingsRate / 100)))
	                                    .tint(savingsRateColor)

	                                Text(savingsRateMessage)
	                                    .font(.caption)
	                                    .foregroundStyle(.secondary)
	                            }
	                            .padding(.top, 4)
	                        }
	                        .padding()
	                        .background(
	                            RoundedRectangle(cornerRadius: 18, style: .continuous)
	                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(savingsRateColor.opacity(0.2), lineWidth: 2)
                        )
                    }

                    // Suggested Amounts
                    if !suggestedAmounts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Suggested Budget Allocation")
                                .font(.headline)

                            Text("Based on the 50/30/20 rule and financial best practices. Adjust amounts to fit your needs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(group.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)

                                        Spacer()

                                        Text(groupTotal(for: group), format: .currency(code: currencyCode))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }

                                    ForEach(group.categories) { category in
                                        HStack(spacing: 12) {
                                            Text(category.name)
                                                .font(.subheadline)

                                            Spacer()

                                            HStack(spacing: 4) {
                                                Text(currencySymbol)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .padding(.leading, 8)

                                                TextField(
                                                    "0",
                                                    text: Binding(
                                                        get: {
                                                            if let custom = customizedAmounts[category.id] {
                                                                return custom
                                                            }
                                                            if let suggested = suggestedAmounts[category.id] {
                                                                return suggested.formatted(.number.precision(.fractionLength(0)))
                                                            }
                                                            return ""
                                                        },
                                                        set: { newValue in
                                                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                                            if trimmed.isEmpty {
                                                                customizedAmounts.removeValue(forKey: category.id)
                                                            } else {
                                                                customizedAmounts[category.id] = trimmed
                                                            }
                                                            calculateSuggestions()
                                                        }
                                                    )
                                                )
                                                .keyboardType(.decimalPad)
                                                .font(.subheadline)
                                                .multilineTextAlignment(.trailing)
                                            }
                                            .frame(width: 100)
                                            .padding(.vertical, 8)
                                            .padding(.trailing, 8)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Budget Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyToMainBudget()
                        dismiss()
                    }
                    .disabled(suggestedAmounts.isEmpty)
                }
            }
        }
    }

    private var savingsRateColor: Color {
        if savingsRate >= 20 {
            return AppColors.success(for: appColorMode)
        } else if savingsRate >= 10 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

    private var savingsRateMessage: String {
        if savingsRate >= 20 {
            return "Excellent! You're saving 20% or more."
        } else if savingsRate >= 10 {
            return "Good start. Try to reach 20% for optimal savings."
        } else if savingsRate >= 0 {
            return "Consider reducing expenses to increase savings."
        } else {
            return "Budget exceeds income. Adjust amounts below."
        }
    }

	    private func groupTotal(for group: BudgetTemplateGroup) -> Decimal {
	        var total: Decimal = 0
	        for category in group.categories {
	            if let amountStr = customizedAmounts[category.id],
	               let amount = Decimal(string: amountStr.replacingOccurrences(of: ",", with: "")) {
	                total += amount
	            } else if let suggested = suggestedAmounts[category.id] {
	                total += suggested
	            }
	        }
	        return total
	    }

	    private func roundToDollar(_ value: Decimal) -> Decimal {
	        (value as NSDecimalNumber).rounding(
	            accordingToBehavior: NSDecimalNumberHandler(
	                roundingMode: .plain,
	                scale: 0,
	                raiseOnExactness: false,
	                raiseOnOverflow: false,
	                raiseOnUnderflow: false,
	                raiseOnDivideByZero: false
	            )
	        ) as Decimal
	    }

	    private func calculateSuggestions() {
	        guard monthlyIncome > 0 else {
	            suggestedAmounts = [:]
	            return
	        }

        // Budget allocation percentages based on best practices
        // Using a refined version of 50/30/20 rule with category-specific allocations
        let categoryAllocation: [String: Double] = [
            // Housing & Utilities (should be ~30% of income)
            "Mortgage": 0.20,
            "Rent": 0.20,
            "Condo Fees": 0.03,
            "Property Taxes": 0.02,
            "Home Improvement": 0.02,
            "Home Insurance": 0.01,
            "Electricity": 0.015,
            "Gas Utility": 0.01,
            "Water Heater": 0.005,
            "Internet": 0.01,

            // Transportation (should be ~15% of income)
            "Auto Insurance": 0.03,
            "Gas": 0.05,
            "Public Transportation": 0.03,
            "Auto Maintenance": 0.02,
            "Parking": 0.01,
            "Tolls": 0.005,

            // Food (should be ~10-15% of income)
            "Groceries & Essentials": 0.10,
            "Restaurants": 0.03,
            "Alcohol & Bars": 0.01,
            "Coffee Shops": 0.01,

            // Phone & Communication (should be ~2-3% of income)
            "Cellphone": 0.025,

            // Entertainment & Lifestyle (should be ~5-10% of income)
            "Entertainment": 0.03,
            "Date Night": 0.02,
            "Subscriptions": 0.02,

            // Health & Fitness (should be ~3-5% of income)
            "Health Services": 0.02,
            "Gym Membership": 0.015,

            // Personal Care (should be ~2-3% of income)
            "Personal Care Services": 0.02,

            // Giving (should be ~3-5% of income)
            "Charity": 0.02,
            "Gifts": 0.02,

            // Children (variable based on household)
            "Child Supplies": 0.03,
            "Child Toys": 0.01,
            "Child Clothing": 0.015,

            // Shopping & Miscellaneous (should be ~5% of income)
            "Services": 0.01,
            "Education": 0.02,
            "Cash": 0.01,
            "Toiletries": 0.01,
            "Makeup": 0.005,
            "Garden": 0.005,
            "Electronics": 0.01,
            "Home": 0.01,
            "Clothing": 0.02,

            // Banking & Fees (should be ~0.5% of income)
            "Banking Fees": 0.005
        ]

	        let targetSpend = roundToDollar(monthlyIncome * (1 - Decimal(targetSavingsRate / 100)))

	        var customTotalForAllocation: Decimal = 0
	        for group in groups {
	            for category in group.categories {
	                if let amountStr = customizedAmounts[category.id],
	                   let amount = Decimal(string: amountStr.replacingOccurrences(of: ",", with: "")) {
	                    customTotalForAllocation += roundToDollar(amount)
	                }
	            }
	        }

	        let remainingSpend = max(Decimal(0), targetSpend - customTotalForAllocation)

	        var weights: [UUID: Double] = [:]
	        var weightSum: Double = 0
	        for group in groups {
	            for category in group.categories {
	                guard customizedAmounts[category.id] == nil else { continue }
	                let weight = categoryAllocation[category.name] ?? 0.01
	                weights[category.id] = weight
	                weightSum += weight
	            }
	        }

	        var newSuggestions: [UUID: Decimal] = [:]
	        if weightSum > 0, remainingSpend > 0 {
	            for group in groups {
	                for category in group.categories {
	                    guard customizedAmounts[category.id] == nil else { continue }
	                    let weight = weights[category.id] ?? 0.01
	                    let raw = remainingSpend * Decimal(weight / weightSum)
	                    newSuggestions[category.id] = roundToDollar(raw)
	                }
	            }
	        } else {
	            for group in groups {
	                for category in group.categories where customizedAmounts[category.id] == nil {
	                    newSuggestions[category.id] = 0
	                }
	            }
	        }

	        // Nudge one category to absorb rounding differences so totals hit the target spend.
	        var roundedTotal = customTotalForAllocation
	        for value in newSuggestions.values { roundedTotal += value }
	        let delta = targetSpend - roundedTotal
	        if delta != 0 {
	            if let adjustID = weights
	                .sorted(by: { $0.value > $1.value })
	                .map(\.key)
	                .first(where: { newSuggestions[$0] != nil }) {
	                newSuggestions[adjustID] = max(Decimal(0), (newSuggestions[adjustID] ?? 0) + delta)
	            }
	        }

	        suggestedAmounts = newSuggestions
	    }

    private func applyToMainBudget() {
        for group in groups {
            for category in group.categories {
                if let custom = customizedAmounts[category.id] {
                    budgetInputs[category.id] = custom
                } else if let suggested = suggestedAmounts[category.id] {
                    budgetInputs[category.id] = suggested.formatted(.number.precision(.fractionLength(0)))
                }
            }
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct BudgetSetupReview: View {
    let groups: [BudgetTemplateGroup]
    let budgetInputs: [UUID: String]
    let currencyCode: String

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? "$"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review plan")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name)
                                .font(.headline)

                            ForEach(group.categories) { category in
                                HStack {
                                    Text(category.name)
                                    Spacer()
                                    Text("\(currencySymbol)\(budgetInputs[category.id] ?? "0")")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Setup Models

private struct BudgetTemplateGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var categories: [BudgetTemplateCategory]

    static let defaults: [BudgetTemplateGroup] = [
        BudgetTemplateGroup(
            id: UUID(),
            name: "Auto & Transport",
            categories: [
                BudgetTemplateCategory(name: "Auto Insurance", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Gas", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Public Transportation", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Auto Maintenance", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Parking", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Tolls", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Bills & Utilities",
            categories: [
                BudgetTemplateCategory(name: "Water Heater", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Banking Fees", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Electricity", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Gas Utility", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Cellphone", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Internet", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Children",
            categories: [
                BudgetTemplateCategory(name: "Child Supplies", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Child Toys", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Child Clothing", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Entertainment",
            categories: [
                BudgetTemplateCategory(name: "Entertainment", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Date Night", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Subscriptions", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Food & Dining",
            categories: [
                BudgetTemplateCategory(name: "Groceries & Essentials", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Restaurants", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Alcohol & Bars", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Coffee Shops", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Giving",
            categories: [
                BudgetTemplateCategory(name: "Charity", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Gifts", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Health & Fitness",
            categories: [
                BudgetTemplateCategory(name: "Health Services", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Gym Membership", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "House",
            categories: [
                BudgetTemplateCategory(name: "Mortgage", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Condo Fees", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Property Taxes", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Home Improvement", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Home Insurance", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Personal Care",
            categories: [
                BudgetTemplateCategory(name: "Personal Care Services", suggestedAmount: 0)
            ]
        ),
        BudgetTemplateGroup(
            id: UUID(),
            name: "Shopping",
            categories: [
                BudgetTemplateCategory(name: "Services", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Education", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Cash", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Toiletries", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Makeup", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Garden", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Electronics", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Home", suggestedAmount: 0),
                BudgetTemplateCategory(name: "Clothing", suggestedAmount: 0)
            ]
        )
    ]
}

private struct BudgetTemplateCategory: Identifiable, Hashable {
    let id: UUID
    var name: String
    var suggestedAmount: Decimal

    init(id: UUID = UUID(), name: String, suggestedAmount: Decimal) {
        self.id = id
        self.name = name
        self.suggestedAmount = suggestedAmount
    }
}

private struct EditableCustomGroup: Identifiable {
    let id = UUID()
    var name: String = ""
    var categories: [String] = [""]
}

private struct CustomGroupEditor: View {
    @State var group: EditableCustomGroup
    let onSave: (EditableCustomGroup) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group Name")) {
                    TextField("Eg. Kids", text: binding(for: \.name))
                }

                Section(header: Text("Categories")) {
                    ForEach(group.categories.indices, id: \.self) { index in
                        TextField("Category", text: binding(forCategoryAt: index))
                    }
                    Button("Add Category") {
                        group.categories.append("")
                    }
                }
            }
            .navigationTitle("Custom Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cleaned = group.categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !cleaned.isEmpty else {
                            onCancel()
                            return
                        }
                        var cleanedGroup = group
                        cleanedGroup.categories = cleaned
                        onSave(cleanedGroup)
                    }
                }
            }
        }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<EditableCustomGroup, Value>) -> Binding<Value> {
        Binding(
            get: { group[keyPath: keyPath] },
            set: { group[keyPath: keyPath] = $0 }
        )
    }

    private func binding(forCategoryAt index: Int) -> Binding<String> {
        Binding(
            get: { group.categories[index] },
            set: { group.categories[index] = $0 }
        )
    }
}

#Preview {
    ManageView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self], inMemory: true)
}
