import Foundation
import SwiftData

final class ReorderCategoriesCommand: Command {
    let description: String = "Reorder Categories"
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
            guard let category = modelContext.model(for: id) as? Category else { continue }
            category.order = order
        }
        try modelContext.save()
    }
}

