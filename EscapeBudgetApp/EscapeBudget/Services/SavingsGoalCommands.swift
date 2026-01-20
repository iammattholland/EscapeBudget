import Foundation
import SwiftData

// MARK: - Add SavingsGoal Command

final class AddSavingsGoalCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var savingsGoal: SavingsGoal?
    private let name: String
    private let targetAmount: Decimal
    private let currentAmount: Decimal
    private let targetDate: Date?
    private let monthlyContribution: Decimal?
    private let colorHex: String
    private let notes: String?
    private let isAchieved: Bool
    private let categoryPersistentID: PersistentIdentifier?
    private let isDemoData: Bool

    init(
        modelContext: ModelContext,
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        monthlyContribution: Decimal? = nil,
        colorHex: String = "007AFF",
        notes: String? = nil,
        isAchieved: Bool = false,
        category: Category? = nil,
        isDemoData: Bool = false
    ) {
        self.modelContext = modelContext
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.monthlyContribution = monthlyContribution
        self.colorHex = colorHex
        self.notes = notes
        self.isAchieved = isAchieved
        self.categoryPersistentID = category?.persistentModelID
        self.isDemoData = isDemoData
        self.description = "Add Savings Goal: \(name)"
    }

    @MainActor
    func execute() throws {
        let newGoal = SavingsGoal(
            name: name,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            targetDate: targetDate,
            monthlyContribution: monthlyContribution,
            colorHex: colorHex,
            notes: notes,
            isAchieved: isAchieved,
            isDemoData: isDemoData
        )

        if let categoryID = categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            newGoal.category = category
        }

        modelContext.insert(newGoal)
        savingsGoal = newGoal

        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let savingsGoal = savingsGoal else {
            throw UndoRedoError.commandExecutionFailed("Savings Goal not found")
        }

        modelContext.delete(savingsGoal)
        try modelContext.save()
        self.savingsGoal = nil
    }
}

// MARK: - Delete SavingsGoal Command

final class DeleteSavingsGoalCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private var savingsGoalPersistentID: PersistentIdentifier
    private var savedData: SavingsGoalSnapshot?

    init(modelContext: ModelContext, savingsGoal: SavingsGoal) {
        self.modelContext = modelContext
        self.savingsGoalPersistentID = savingsGoal.persistentModelID
        self.description = "Delete Savings Goal: \(savingsGoal.name)"
    }

    @MainActor
    func execute() throws {
        guard let savingsGoal = modelContext.model(for: savingsGoalPersistentID) as? SavingsGoal else {
            throw UndoRedoError.commandExecutionFailed("Savings Goal not found")
        }

        savedData = SavingsGoalSnapshot(from: savingsGoal)
        modelContext.delete(savingsGoal)
        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let snapshot = savedData else {
            throw UndoRedoError.commandExecutionFailed("No saved data to restore")
        }

        let newGoal = SavingsGoal(
            name: snapshot.name,
            targetAmount: snapshot.targetAmount,
            currentAmount: snapshot.currentAmount,
            targetDate: snapshot.targetDate,
            monthlyContribution: snapshot.monthlyContribution,
            colorHex: snapshot.colorHex,
            notes: snapshot.notes,
            isAchieved: snapshot.isAchieved,
            isDemoData: snapshot.isDemoData
        )

        if let categoryID = snapshot.categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            newGoal.category = category
        }

        modelContext.insert(newGoal)
        try modelContext.save()

        // Update the persistent ID to the newly created savings goal
        savingsGoalPersistentID = newGoal.persistentModelID
    }
}

// MARK: - Update SavingsGoal Command

final class UpdateSavingsGoalCommand: Command {
    let description: String
    private let modelContext: ModelContext
    private let savingsGoalPersistentID: PersistentIdentifier
    private let oldSnapshot: SavingsGoalSnapshot
    private let newSnapshot: SavingsGoalSnapshot

    init(
        modelContext: ModelContext,
        savingsGoal: SavingsGoal,
        newName: String,
        newTargetAmount: Decimal,
        newCurrentAmount: Decimal,
        newTargetDate: Date?,
        newMonthlyContribution: Decimal?,
        newColorHex: String,
        newNotes: String?,
        newIsAchieved: Bool,
        newCategory: Category?
    ) {
        self.modelContext = modelContext
        self.savingsGoalPersistentID = savingsGoal.persistentModelID
        self.oldSnapshot = SavingsGoalSnapshot(from: savingsGoal)
        self.newSnapshot = SavingsGoalSnapshot(
            name: newName,
            targetAmount: newTargetAmount,
            currentAmount: newCurrentAmount,
            targetDate: newTargetDate,
            monthlyContribution: newMonthlyContribution,
            colorHex: newColorHex,
            notes: newNotes,
            isAchieved: newIsAchieved,
            categoryPersistentID: newCategory?.persistentModelID,
            isDemoData: savingsGoal.isDemoData
        )
        self.description = "Update Savings Goal: \(savingsGoal.name)"
    }

    @MainActor
    func execute() throws {
        guard let savingsGoal = modelContext.model(for: savingsGoalPersistentID) as? SavingsGoal else {
            throw UndoRedoError.commandExecutionFailed("Savings Goal not found")
        }

        applySnapshot(newSnapshot, to: savingsGoal)
        try modelContext.save()
    }

    @MainActor
    func undo() throws {
        guard let savingsGoal = modelContext.model(for: savingsGoalPersistentID) as? SavingsGoal else {
            throw UndoRedoError.commandExecutionFailed("Savings Goal not found")
        }

        applySnapshot(oldSnapshot, to: savingsGoal)
        try modelContext.save()
    }

    private func applySnapshot(_ snapshot: SavingsGoalSnapshot, to savingsGoal: SavingsGoal) {
        savingsGoal.name = snapshot.name
        savingsGoal.targetAmount = snapshot.targetAmount
        savingsGoal.currentAmount = snapshot.currentAmount
        savingsGoal.targetDate = snapshot.targetDate
        savingsGoal.monthlyContribution = snapshot.monthlyContribution
        savingsGoal.colorHex = snapshot.colorHex
        savingsGoal.notes = snapshot.notes
        savingsGoal.isAchieved = snapshot.isAchieved

        if let categoryID = snapshot.categoryPersistentID,
           let category = modelContext.model(for: categoryID) as? Category {
            savingsGoal.category = category
        } else {
            savingsGoal.category = nil
        }
    }
}

// MARK: - SavingsGoal Snapshot

struct SavingsGoalSnapshot {
    let name: String
    let targetAmount: Decimal
    let currentAmount: Decimal
    let targetDate: Date?
    let monthlyContribution: Decimal?
    let colorHex: String
    let notes: String?
    let isAchieved: Bool
    let categoryPersistentID: PersistentIdentifier?
    let isDemoData: Bool

    init(from savingsGoal: SavingsGoal) {
        self.name = savingsGoal.name
        self.targetAmount = savingsGoal.targetAmount
        self.currentAmount = savingsGoal.currentAmount
        self.targetDate = savingsGoal.targetDate
        self.monthlyContribution = savingsGoal.monthlyContribution
        self.colorHex = savingsGoal.colorHex
        self.notes = savingsGoal.notes
        self.isAchieved = savingsGoal.isAchieved
        self.categoryPersistentID = savingsGoal.category?.persistentModelID
        self.isDemoData = savingsGoal.isDemoData
    }

    init(
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal,
        targetDate: Date?,
        monthlyContribution: Decimal?,
        colorHex: String,
        notes: String?,
        isAchieved: Bool,
        categoryPersistentID: PersistentIdentifier?,
        isDemoData: Bool
    ) {
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.monthlyContribution = monthlyContribution
        self.colorHex = colorHex
        self.notes = notes
        self.isAchieved = isAchieved
        self.categoryPersistentID = categoryPersistentID
        self.isDemoData = isDemoData
    }
}
