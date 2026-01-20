import Foundation
import SwiftData

// MARK: - Add Category Command

final class AddCategoryCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var category: Category?
    private let name: String
    private let assigned: Decimal
    private let activity: Decimal
    private let order: Int
    private let icon: String?
    private let memo: String?
    private let groupPersistentID: PersistentIdentifier?
    private let isDemoData: Bool

    init(
        modelContext: ModelContext,
        name: String,
        assigned: Decimal = 0.0,
        activity: Decimal = 0.0,
        order: Int = 0,
        icon: String? = nil,
        memo: String? = nil,
        group: CategoryGroup? = nil,
        isDemoData: Bool = false
    ) {
        self.modelContext = modelContext
        self.name = name
        self.assigned = assigned
        self.activity = activity
        self.order = order
        self.icon = icon
        self.memo = memo
        self.groupPersistentID = group?.persistentModelID
        self.isDemoData = isDemoData
        self.description = "Add Category: \(name)"
    }

    @MainActor
    func execute() throws {
        let newCategory = Category(
            name: name,
            assigned: assigned,
            activity: activity,
            order: order,
            icon: icon,
            memo: memo,
            isDemoData: isDemoData
        )

        // Restore relationship
        if let groupID = groupPersistentID,
           let group = modelContext.model(for: groupID) as? CategoryGroup {
            newCategory.group = group
        }

        modelContext.insert(newCategory)
        category = newCategory

        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let category = category else {
            throw UndoRedoError.commandExecutionFailed("Category not found")
        }

        modelContext.delete(category)
        try modelContext.save()
        self.category = nil
    }
}

// MARK: - Delete Category Command

final class DeleteCategoryCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var categoryPersistentID: PersistentIdentifier
    private var savedData: CategorySnapshot?

    init(modelContext: ModelContext, category: Category) {
        self.modelContext = modelContext
        self.categoryPersistentID = category.persistentModelID
        self.description = "Delete Category: \(category.name)"
    }

    @MainActor
    func execute() throws {
        guard let category = modelContext.model(for: categoryPersistentID) as? Category else {
            throw UndoRedoError.commandExecutionFailed("Category not found")
        }

        // Save data for undo
        savedData = CategorySnapshot(from: category)

        modelContext.delete(category)
        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let snapshot = savedData else {
            throw UndoRedoError.commandExecutionFailed("No saved data to restore")
        }

        let newCategory = Category(
            name: snapshot.name,
            assigned: snapshot.assigned,
            activity: snapshot.activity,
            order: snapshot.order,
            icon: snapshot.icon,
            memo: snapshot.memo,
            isDemoData: snapshot.isDemoData
        )

        // Restore relationship
        if let groupID = snapshot.groupPersistentID,
           let group = modelContext.model(for: groupID) as? CategoryGroup {
            newCategory.group = group
        }

        modelContext.insert(newCategory)
        try modelContext.save()

        // Update the persistent ID to the newly created category
        categoryPersistentID = newCategory.persistentModelID
    }
}

// MARK: - Update Category Command

final class UpdateCategoryCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let categoryPersistentID: PersistentIdentifier
    private let oldSnapshot: CategorySnapshot
    private let newSnapshot: CategorySnapshot

    init(
        modelContext: ModelContext,
        category: Category,
        newName: String,
        newAssigned: Decimal,
        newActivity: Decimal,
        newOrder: Int,
        newIcon: String?,
        newMemo: String?,
        newGroup: CategoryGroup?
    ) {
        self.modelContext = modelContext
        self.categoryPersistentID = category.persistentModelID
        self.oldSnapshot = CategorySnapshot(from: category)
        self.newSnapshot = CategorySnapshot(
            name: newName,
            assigned: newAssigned,
            activity: newActivity,
            order: newOrder,
            icon: newIcon,
            memo: newMemo,
            groupPersistentID: newGroup?.persistentModelID,
            isDemoData: category.isDemoData
        )
        self.description = "Update Category: \(category.name)"
    }

    @MainActor
    func execute() throws {
        guard let category = modelContext.model(for: categoryPersistentID) as? Category else {
            throw UndoRedoError.commandExecutionFailed("Category not found")
        }

        applySnapshot(newSnapshot, to: category)
        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let category = modelContext.model(for: categoryPersistentID) as? Category else {
            throw UndoRedoError.commandExecutionFailed("Category not found")
        }

        applySnapshot(oldSnapshot, to: category)
        try modelContext.save()
    }

    private func applySnapshot(_ snapshot: CategorySnapshot, to category: Category) {
        category.name = snapshot.name
        category.assigned = snapshot.assigned
        category.activity = snapshot.activity
        category.order = snapshot.order
        category.icon = snapshot.icon
        category.memo = snapshot.memo

        if let groupID = snapshot.groupPersistentID,
           let group = modelContext.model(for: groupID) as? CategoryGroup {
            category.group = group
        } else {
            category.group = nil
        }
    }
}

// MARK: - Bulk Move Categories Command

final class BulkMoveCategoriesCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let destinationGroupID: PersistentIdentifier
    private let categoryIDs: [PersistentIdentifier]
    private let oldSnapshots: [PersistentIdentifier: CategorySnapshot]
    private let newSnapshots: [PersistentIdentifier: CategorySnapshot]

    init(
        modelContext: ModelContext,
        categories: [Category],
        destinationGroup: CategoryGroup
    ) {
        self.modelContext = modelContext
        self.destinationGroupID = destinationGroup.persistentModelID

        let orderedCategories = categories.sorted { lhs, rhs in
            if lhs.group?.order != rhs.group?.order {
                return (lhs.group?.order ?? 0) < (rhs.group?.order ?? 0)
            }
            return lhs.order < rhs.order
        }
        self.categoryIDs = orderedCategories.map(\.persistentModelID)

        var old: [PersistentIdentifier: CategorySnapshot] = [:]
        for category in orderedCategories {
            old[category.persistentModelID] = CategorySnapshot(from: category)
        }
        self.oldSnapshots = old

        // Assign new orders appended to destination group, preserving selection ordering.
        let destinationMaxOrder = (destinationGroup.categories ?? []).map(\.order).max() ?? -1
        var nextOrder = destinationMaxOrder + 1

        var new: [PersistentIdentifier: CategorySnapshot] = [:]
        for category in orderedCategories {
            new[category.persistentModelID] = CategorySnapshot(
                name: category.name,
                assigned: category.assigned,
                activity: category.activity,
                order: nextOrder,
                icon: category.icon,
                memo: category.memo,
                groupPersistentID: destinationGroup.persistentModelID,
                isDemoData: category.isDemoData
            )
            nextOrder += 1
        }
        self.newSnapshots = new

        self.description = "Move \(orderedCategories.count) Categories to \(destinationGroup.name)"
    }

    @MainActor
    func execute() throws {
        try apply(snapshots: newSnapshots)
    }

    @MainActor
    func undo() throws {
        try apply(snapshots: oldSnapshots)
    }

    @MainActor
    private func apply(snapshots: [PersistentIdentifier: CategorySnapshot]) throws {
        guard let destinationGroup = modelContext.model(for: destinationGroupID) as? CategoryGroup else {
            throw UndoRedoError.commandExecutionFailed("Destination group not found")
        }

        for id in categoryIDs {
            guard let snapshot = snapshots[id],
                  let category = modelContext.model(for: id) as? Category
            else { continue }

            category.name = snapshot.name
            category.assigned = snapshot.assigned
            category.activity = snapshot.activity
            category.order = snapshot.order
            category.icon = snapshot.icon
            category.memo = snapshot.memo

            if snapshot.groupPersistentID == destinationGroup.persistentModelID {
                category.group = destinationGroup
            } else if let groupID = snapshot.groupPersistentID,
                      let group = modelContext.model(for: groupID) as? CategoryGroup {
                category.group = group
            } else {
                category.group = nil
            }
        }

        try modelContext.save()
    }
}

// MARK: - Category Snapshot

struct CategorySnapshot {
    let name: String
    let assigned: Decimal
    let activity: Decimal
    let order: Int
    let icon: String?
    let memo: String?
    let groupPersistentID: PersistentIdentifier?
    let isDemoData: Bool

    init(from category: Category) {
        self.name = category.name
        self.assigned = category.assigned
        self.activity = category.activity
        self.order = category.order
        self.icon = category.icon
        self.memo = category.memo
        self.groupPersistentID = category.group?.persistentModelID
        self.isDemoData = category.isDemoData
    }

    init(
        name: String,
        assigned: Decimal,
        activity: Decimal,
        order: Int,
        icon: String?,
        memo: String?,
        groupPersistentID: PersistentIdentifier?,
        isDemoData: Bool
    ) {
        self.name = name
        self.assigned = assigned
        self.activity = activity
        self.order = order
        self.icon = icon
        self.memo = memo
        self.groupPersistentID = groupPersistentID
        self.isDemoData = isDemoData
    }
}
