import Foundation
import SwiftData

final class AddCategoryGroupCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var group: CategoryGroup?
    private(set) var createdGroupID: PersistentIdentifier?
    private let name: String
    private let order: Int
    private let type: CategoryGroupType
    private let isDemoData: Bool

    init(
        modelContext: ModelContext,
        name: String,
        order: Int,
        type: CategoryGroupType = .expense,
        isDemoData: Bool = false
    ) {
        self.modelContext = modelContext
        self.name = name
        self.order = order
        self.type = type
        self.isDemoData = isDemoData
        self.description = "Add Category Group: \(name)"
    }

    @MainActor
    func execute() throws {
        let newGroup = CategoryGroup(name: name, order: order, type: type, isDemoData: isDemoData)
        modelContext.insert(newGroup)
        group = newGroup
        try modelContext.save()
        createdGroupID = newGroup.persistentModelID
    }

    @MainActor
    func undo() throws {
        guard let group else {
            throw UndoRedoError.commandExecutionFailed("Category group not found")
        }
        modelContext.delete(group)
        try modelContext.save()
        self.group = nil
        self.createdGroupID = nil
    }
}

final class ReorderCategoryGroupsCommand: Command {
    let description: String = "Reorder Category Groups"
    private let modelContext: ModelContext
    private let oldOrders: [PersistentIdentifier: Int]
    private let newOrders: [PersistentIdentifier: Int]

    init(
        modelContext: ModelContext,
        oldOrders: [PersistentIdentifier: Int],
        newOrders: [PersistentIdentifier: Int]
    ) {
        self.modelContext = modelContext
        self.oldOrders = oldOrders
        self.newOrders = newOrders
    }

    @MainActor
    func execute() throws {
        try apply(orders: newOrders)
    }

    @MainActor
    func undo() throws {
        try apply(orders: oldOrders)
    }

    @MainActor
    private func apply(orders: [PersistentIdentifier: Int]) throws {
        for (id, order) in orders {
            guard let group = modelContext.model(for: id) as? CategoryGroup else { continue }
            group.order = order
        }
        try modelContext.save()
    }
}
