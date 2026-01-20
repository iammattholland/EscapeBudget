import SwiftUI
import SwiftData

struct SmartCategorizeReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @Query(sort: \Category.name) private var allCategories: [Category]

    let transactions: [Transaction]

    @State private var suggestions: [BulkCategorizationSuggester.SuggestionGroup] = []
    @State private var isLoading = true
    @State private var selectedCategories: [UUID: Category] = [:] // groupID -> Category
    @State private var selectedTransactionIDsByGroup: [UUID: Set<PersistentIdentifier>] = [:] // groupID -> tx IDs
    @State private var errorMessage: String?
    @State private var showingCategoryPicker = false
    @State private var categoryPickerGroupID: UUID?
    @State private var dismissedGroups: Set<UUID> = []

    private var availableCategories: [Category] {
        allCategories.filter { $0.group?.type != .transfer }
    }

    private var canApply: Bool {
        totalTransactionsToCategize > 0
    }

    private var totalTransactionsToCategize: Int {
        suggestions
            .filter { selectedCategories[$0.id] != nil && !dismissedGroups.contains($0.id) }
            .reduce(0) { total, group in
                total + (selectedTransactionIDsByGroup[group.id]?.count ?? 0)
            }
    }

    private var visibleSuggestions: [BulkCategorizationSuggester.SuggestionGroup] {
        suggestions.filter { !dismissedGroups.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Analyzing transactions...")
                } else if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No Suggestions",
                        systemImage: "sparkles",
                        description: Text("No categorization patterns found. Try categorizing a few transactions manually first.")
                    )
                } else {
                    suggestionsList
                }
            }
            .navigationTitle("Smart Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applySelections()
                    }
                    .disabled(!canApply)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                if let groupID = categoryPickerGroupID {
                    categoryPickerSheet(for: groupID)
                }
            }
            .task {
                await loadSuggestions()
            }
        }
    }

    private var suggestionsList: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.danger(for: appColorMode))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        Text("Found \(visibleSuggestions.count) suggestion group\(visibleSuggestions.count == 1 ? "" : "s")")
                            .appSectionTitleText()
                    }

                    if totalTransactionsToCategize > 0 {
                        Text("\(totalTransactionsToCategize) transaction\(totalTransactionsToCategize == 1 ? "" : "s") selected to categorize")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }

                    if !dismissedGroups.isEmpty {
                        Text("\(dismissedGroups.count) group\(dismissedGroups.count == 1 ? "" : "s") dismissed (swipe to dismiss)")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.micro)
            }

            ForEach(visibleSuggestions) { group in
                suggestionRow(for: group)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                dismissGroup(group)
                            }
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(for group: BulkCategorizationSuggester.SuggestionGroup) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
                // Payee and transaction count
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                        HStack(spacing: AppTheme.Spacing.xSmall) {
                            Text(group.displayPayee)
                                .appSectionTitleText()

                            if group.isTransferLikely {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .appCaptionText()
                                    .foregroundStyle(.orange)
                            }
                        }

                        HStack(spacing: AppTheme.Spacing.micro) {
                            Text("\(group.transactions.count) transaction\(group.transactions.count == 1 ? "" : "s")")
                                .appCaptionText()
                                .foregroundStyle(.secondary)

                            if group.confidence > 0 {
                                Text("•")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)

                                HStack(spacing: AppTheme.Spacing.hairline) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.caption2)
                                    Text("\(Int(group.confidence * 100))%")
                                        .appCaptionText()
                                }
                                .foregroundStyle(confidenceColor(group.confidence))
                            }
                        }

                        if group.isTransferLikely {
                            Text("Likely transfer - consider categorizing as Transfer")
                                .appCaptionText()
                                .foregroundStyle(.orange)
                        } else if let reason = group.reason, !reason.isEmpty, group.suggestedCategory != nil {
                            Text(reason)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(group.totalAmount, format: .currency(code: currencyCode))
                        .appSecondaryBodyText()
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                // Category selection
                if let selectedCategory = selectedCategories[group.id] {
                    Button {
                        categoryPickerGroupID = group.id
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(selectedCategory.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else if let suggested = group.suggestedCategory {
                    HStack(spacing: AppTheme.Spacing.tight) {
                        Button {
                            selectedCategories[group.id] = suggested
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                                Text(suggested.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Accept")
                                    .appSecondaryBodyText()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, AppTheme.Spacing.tight)
                                    .padding(.vertical, AppTheme.Spacing.xSmall)
                                    .background(AppColors.tint(for: appColorMode), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        categoryPickerGroupID = group.id
                        showingCategoryPicker = true
                    } label: {
                        Text("Change")
                            .appCaptionText()
                            .foregroundStyle(AppColors.tint(for: appColorMode))
                    }
                } else {
                    Button {
                        categoryPickerGroupID = group.id
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text("Select Category")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    SmartCategorizeGroupDetailView(
                        group: group,
                        currencyCode: currencyCode,
                        selectedIDs: Binding(
                            get: { selectedTransactionIDsByGroup[group.id] ?? Set(group.transactions.map(\.persistentModelID)) },
                            set: { selectedTransactionIDsByGroup[group.id] = $0 }
                        )
                    )
                } label: {
                    let selectedCount = selectedTransactionIDsByGroup[group.id]?.count ?? group.transactions.count
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(.secondary)
                        Text("Review transactions")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(selectedCount)/\(group.transactions.count)")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, AppTheme.Spacing.micro)
        }
    }

    @ViewBuilder
    private func categoryPickerSheet(for groupID: UUID) -> some View {
        NavigationStack {
            categoryPickerList(for: groupID)
                .navigationTitle("Select Category")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingCategoryPicker = false
                        }
                    }
                }
        }
    }

    private func categoryPickerList(for groupID: UUID) -> some View {
        List {
            Section {
                Button {
                    selectedCategories.removeValue(forKey: groupID)
                    showingCategoryPicker = false
                } label: {
                    HStack {
                        Text("Don't Categorize")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if selectedCategories[groupID] == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            categoryGroupSections(for: groupID)
        }
    }

    @ViewBuilder
    private func categoryGroupSections(for groupID: UUID) -> some View {
        let groupedByID = Dictionary(grouping: availableCategories) { $0.group?.persistentModelID }
        let sortedPairs = groupedByID.sorted { lhs, rhs in
            let lhsOrder = lhs.value.first?.group?.order ?? 0
            let rhsOrder = rhs.value.first?.group?.order ?? 0
            return lhsOrder < rhsOrder
        }

        ForEach(sortedPairs, id: \.key) { pair in
            let groupName = pair.value.first?.group?.name ?? "Uncategorized"
            let sortedCategories = pair.value.sorted(by: { $0.order < $1.order })

            Section(groupName) {
                ForEach(sortedCategories) { category in
                    Button {
                        selectedCategories[groupID] = category
                        showingCategoryPicker = false
                    } label: {
                        HStack {
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategories[groupID]?.persistentModelID == category.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .orange }
        return .secondary
    }

    @MainActor
    private func loadSuggestions() async {
        isLoading = true
        defer { isLoading = false }

        let suggester = BulkCategorizationSuggester(modelContext: modelContext)
        suggestions = suggester.generateSuggestions(for: transactions)

        selectedTransactionIDsByGroup = Dictionary(
            uniqueKeysWithValues: suggestions.map { group in
                (group.id, Set(group.transactions.map(\.persistentModelID)))
            }
        )

        // Auto-select high-confidence suggestions
        for suggestion in suggestions where suggestion.confidence >= 0.85 {
            if let category = suggestion.suggestedCategory {
                selectedCategories[suggestion.id] = category
            }
        }
    }

    private func dismissGroup(_ group: BulkCategorizationSuggester.SuggestionGroup) {
        dismissedGroups.insert(group.id)
        selectedCategories.removeValue(forKey: group.id)
        selectedTransactionIDsByGroup.removeValue(forKey: group.id)
    }

    private func applySelections() {
        errorMessage = nil

        let suggester = BulkCategorizationSuggester(modelContext: modelContext)

        do {
            for suggestion in visibleSuggestions {
                if let category = selectedCategories[suggestion.id] {
                    let selectedIDs = selectedTransactionIDsByGroup[suggestion.id] ?? Set(suggestion.transactions.map(\.persistentModelID))
                    guard !selectedIDs.isEmpty else { continue }
                    try suggester.applySuggestion(group: suggestion, category: category, selectedTransactionIDs: selectedIDs)
                }
            }

            dismiss()
        } catch {
            errorMessage = "Failed to apply categorizations. Please try again."
        }
    }
}

private struct SmartCategorizeGroupDetailView: View {
    let group: BulkCategorizationSuggester.SuggestionGroup
    let currencyCode: String
    @Binding var selectedIDs: Set<PersistentIdentifier>

    private var sortedTransactions: [Transaction] {
        group.transactions.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                        Text(group.displayPayee)
                            .appSectionTitleText()
                        Text("\(selectedIDs.count) selected")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(group.totalAmount, format: .currency(code: currencyCode))
                        .appSecondaryBodyText()
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }

            Section {
                ForEach(sortedTransactions) { transaction in
                    let isSelected = selectedIDs.contains(transaction.persistentModelID)
                    Button {
                        if isSelected {
                            selectedIDs.remove(transaction.persistentModelID)
                        } else {
                            selectedIDs.insert(transaction.persistentModelID)
                        }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.tight) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.nano) {
                                Text(transaction.payee)
                                    .foregroundStyle(.primary)
                                HStack(spacing: AppTheme.Spacing.xSmall) {
                                    Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                                    if let accountName = transaction.account?.name, !accountName.isEmpty {
                                        Text("•")
                                        Text(accountName)
                                    }
                                }
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(transaction.amount, format: .currency(code: currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select All") {
                        selectedIDs = Set(group.transactions.map(\.persistentModelID))
                    }
                    Button("Deselect All") {
                        selectedIDs = []
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
