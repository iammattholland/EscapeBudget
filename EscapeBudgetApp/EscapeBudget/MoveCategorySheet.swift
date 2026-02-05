import SwiftData
import SwiftUI

struct MoveCategorySheet: View {
    let category: Category
    let targetTypeOverride: CategoryGroupType?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoRedoManager) private var undoRedoManager

    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]

    @State private var searchText = ""
    @State private var newGroupName = ""
    @State private var isCreatingGroup = false
    @State private var targetTypeSelection: CategoryGroupType

    init(category: Category, targetTypeOverride: CategoryGroupType? = nil) {
        self.category = category
        self.targetTypeOverride = targetTypeOverride
        let initial = targetTypeOverride ?? category.group?.type ?? .expense
        _targetTypeSelection = State(initialValue: initial == .income ? .income : .expense)
    }

    private var currentGroupID: PersistentIdentifier? {
        category.group?.persistentModelID
    }

    private var eligibleGroups: [CategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryGroups
            .filter { $0.type == targetTypeSelection }
            .filter { trimmed.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.order < $1.order }
    }

    private var canCreateNewGroup: Bool { targetTypeSelection != .transfer }

    private var recentGroups: [CategoryGroup] {
        RecentBudgetGroupStore.resolve(from: categoryGroups, requiredType: targetTypeSelection)
            .filter { $0.persistentModelID != currentGroupID }
    }

    private var availableTargetTypes: [CategoryGroupType] {
        [.expense, .income]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Current Group") {
                        Text(category.group?.name ?? "None")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Destination Type") {
                    Picker("Destination Type", selection: $targetTypeSelection) {
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
                                        moveCategory(to: group)
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
                                moveCategory(to: group)
                            } label: {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    if group.persistentModelID == currentGroupID {
                                        Text("Current")
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(group.persistentModelID == currentGroupID)
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
            .navigationTitle("Move Category")
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

    private func moveCategory(to destinationGroup: CategoryGroup) {
        let destinationMaxOrder = (destinationGroup.categories ?? []).map(\.order).max() ?? -1

        withAnimation {
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
                        newGroup: destinationGroup
                    )
                )
            } catch {
                category.group = destinationGroup
                category.order = destinationMaxOrder + 1
                modelContext.safeSave(context: "MoveCategorySheet.moveCategory.fallback")
            }

            RecentBudgetGroupStore.record(group: destinationGroup)
            dismiss()
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
                type: targetTypeSelection
            )
            try undoRedoManager.execute(addCommand)

            if let newGroupID = addCommand.createdGroupID,
               let newGroup = modelContext.model(for: newGroupID) as? CategoryGroup {
                moveCategory(to: newGroup)
            } else {
                modelContext.safeSave(context: "MoveCategorySheet.createGroupAndMove.missingGroup.fallback")
            }
        } catch {
            let newGroup = CategoryGroup(name: trimmedName, order: maxOrder + 1, type: targetTypeSelection)
            modelContext.insert(newGroup)
            modelContext.safeSave(context: "MoveCategorySheet.createGroupAndMove.insertGroup.fallback")
            moveCategory(to: newGroup)
        }
    }
}
