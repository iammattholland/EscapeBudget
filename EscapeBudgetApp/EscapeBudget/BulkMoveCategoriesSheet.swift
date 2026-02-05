import SwiftData
import SwiftUI

struct BulkMoveCategoriesSheet: View {
    let categoryIDs: [PersistentIdentifier]
    let requiredType: CategoryGroupType
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager

    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]

    @State private var searchText = ""
    @State private var newGroupName = ""
    @State private var isCreatingGroup = false
    @State private var targetType: CategoryGroupType

    init(
        categoryIDs: [PersistentIdentifier],
        requiredType: CategoryGroupType,
        onComplete: @escaping () -> Void = {}
    ) {
        self.categoryIDs = categoryIDs
        self.requiredType = requiredType
        self.onComplete = onComplete
        _targetType = State(initialValue: requiredType == .income ? .income : .expense)
    }

    private var availableTargetTypes: [CategoryGroupType] {
        [.expense, .income]
    }

    private var recentGroups: [CategoryGroup] {
        RecentBudgetGroupStore.resolve(from: categoryGroups, requiredType: targetType)
    }

    private var eligibleGroups: [CategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryGroups
            .filter { $0.type == targetType }
            .filter { trimmed.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.order < $1.order }
    }

    private var canCreateNewGroup: Bool {
        targetType != .transfer
    }

    private var selectedCategories: [Category] {
        categoryIDs.compactMap { modelContext.model(for: $0) as? Category }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Selected") {
                        Text("\(selectedCategories.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Destination Type") {
                    Picker("Destination Type", selection: $targetType) {
                        ForEach(availableTargetTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !recentGroups.isEmpty {
                    Section("Recent") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppDesign.Theme.Spacing.small) {
                                ForEach(recentGroups) { group in
                                    Button {
                                        moveCategories(to: group)
                                    } label: {
                                        Text(group.name)
                                            .font(AppDesign.Theme.Typography.secondaryBody.weight(.semibold))
                                            .padding(.horizontal, AppDesign.Theme.Spacing.cardPadding)
                                            .padding(.vertical, AppDesign.Theme.Spacing.small)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(AppDesign.Theme.Radius.button)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, AppDesign.Theme.Spacing.micro)
                        }
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                    }
                }

                Section("Move To") {
                    if eligibleGroups.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(eligibleGroups) { group in
                            Button {
                                moveCategories(to: group)
                            } label: {
                                Text(group.name)
                            }
                        }
                    }
                }

                if canCreateNewGroup {
                    Section("New Group") {
                        TextField("Group name", text: $newGroupName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .disabled(isCreatingGroup)

                        Button("Create and Move") {
                            createGroupAndMove()
                        }
                        .disabled(isCreatingGroup || newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Move Categories")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .solidPresentationBackground()
    }

    private func moveCategories(to destinationGroup: CategoryGroup) {
        let categories = selectedCategories
        guard !categories.isEmpty else { return }

        withAnimation {
            do {
                try undoRedoManager.execute(
                    BulkMoveCategoriesCommand(
                        modelContext: modelContext,
                        categories: categories,
                        destinationGroup: destinationGroup
                    )
                )
            } catch {
                let destinationMaxOrder = (destinationGroup.categories ?? []).map(\.order).max() ?? -1
                var nextOrder = destinationMaxOrder + 1
                for category in categories {
                    category.group = destinationGroup
                    category.order = nextOrder
                    nextOrder += 1
                }
                modelContext.safeSave(context: "BulkMoveCategoriesSheet.moveCategories.fallback")
            }

            RecentBudgetGroupStore.record(group: destinationGroup)
            dismiss()
            onComplete()
        }
    }

    private func createGroupAndMove() {
        guard canCreateNewGroup else { return }

        let trimmedName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isCreatingGroup = true
        defer { isCreatingGroup = false }

        let maxOrder = categoryGroups.map(\.order).max() ?? -1

        do {
            let addCommand = AddCategoryGroupCommand(
                modelContext: modelContext,
                name: trimmedName,
                order: maxOrder + 1,
                type: targetType
            )
            try undoRedoManager.execute(addCommand)

            if let newGroupID = addCommand.createdGroupID,
               let newGroup = modelContext.model(for: newGroupID) as? CategoryGroup {
                moveCategories(to: newGroup)
            } else {
                modelContext.safeSave(context: "BulkMoveCategoriesSheet.createGroupAndMove.missingGroup.fallback")
            }
        } catch {
            let newGroup = CategoryGroup(name: trimmedName, order: maxOrder + 1, type: targetType)
            modelContext.insert(newGroup)
            modelContext.safeSave(context: "BulkMoveCategoriesSheet.createGroupAndMove.insertGroup.fallback")
            moveCategories(to: newGroup)
        }
    }
}
