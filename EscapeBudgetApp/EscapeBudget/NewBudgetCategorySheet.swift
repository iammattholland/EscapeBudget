import SwiftUI
import SwiftData

struct NewBudgetCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryGroup.order) private var categoryGroups: [CategoryGroup]

    let initialGroup: CategoryGroup?
    let createdAtMonthStart: Date?
    let onCreated: (Category) -> Void

    @State private var creatingNewGroup = false
    @State private var selectedGroup: CategoryGroup?
    @State private var newGroupName = ""
    @State private var newGroupType: CategoryGroupType = .expense

    @State private var categoryName = ""

    init(
        initialGroup: CategoryGroup? = nil,
        createdAtMonthStart: Date? = nil,
        onCreated: @escaping (Category) -> Void
    ) {
        self.initialGroup = initialGroup
        self.createdAtMonthStart = createdAtMonthStart
        self.onCreated = onCreated
        _selectedGroup = State(initialValue: initialGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    Toggle("Create New Group", isOn: $creatingNewGroup)

                    if creatingNewGroup {
                        TextField("New group name", text: $newGroupName)

                        Picker("Type", selection: $newGroupType) {
                            Text("Expense").tag(CategoryGroupType.expense)
                            Text("Income").tag(CategoryGroupType.income)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Group", selection: $selectedGroup) {
                            Text("Select").tag(nil as CategoryGroup?)
                            ForEach(categoryGroups.filter { $0.type != .transfer }) { group in
                                Text(group.name).tag(group as CategoryGroup?)
                            }
                        }
                    }
                }

                Section("Category Name") {
                    TextField("Groceries", text: $categoryName)
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { createCategory() }
                        .disabled(addDisabled)
                }
            }
        }
        .presentationDetents([.medium])
        .solidPresentationBackground()
        .onAppear {
            if selectedGroup == nil {
                selectedGroup = categoryGroups.first(where: { $0.type != .transfer })
            }
        }
    }

    private var addDisabled: Bool {
        let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty else { return true }
        if creatingNewGroup {
            return newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedGroup == nil
    }

    @MainActor
    private func createCategory() {
        let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty else { return }

        let group: CategoryGroup
        if creatingNewGroup {
            let trimmedGroup = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedGroup.isEmpty else { return }
            guard newGroupType != .transfer else { return }

            let nextGroupOrder = (categoryGroups.map(\.order).max() ?? -1) + 1
            let createdGroup = CategoryGroup(name: trimmedGroup, order: nextGroupOrder, type: newGroupType)
            modelContext.insert(createdGroup)
            group = createdGroup
            selectedGroup = createdGroup
        } else {
            guard let selectedGroup else { return }
            group = selectedGroup
        }

        let nextCategoryOrder = ((group.categories ?? []).map(\.order).max() ?? -1) + 1
        let category = Category(name: trimmedCategory, assigned: 0, activity: 0, order: nextCategoryOrder)
        category.group = group
        if let createdAtMonthStart {
            category.createdAt = createdAtMonthStart
        }

        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        modelContext.insert(category)

        do {
            try modelContext.save()
            onCreated(category)
            dismiss()
        } catch {
            // No-op: keep the sheet open so the user can try again.
        }
    }
}
