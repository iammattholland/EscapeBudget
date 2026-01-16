import Foundation
import SwiftData
import SwiftUI

// MARK: - Command Protocol

/// Protocol that defines an undoable/redoable command
@MainActor
protocol Command {
    /// Description of the action for display purposes
    var description: String { get }

    /// Execute the command
    @MainActor
    func execute() throws

    /// Undo the command
    @MainActor
    func undo() throws
}

// MARK: - Undo/Redo Manager

/// Manages undo/redo operations throughout the app
@Observable
class UndoRedoManager {
    private var undoStack: [Command] = []
    private var redoStack: [Command] = []

    /// Maximum number of undo operations to keep in memory
    private let maxStackSize: Int = 50

    /// Whether undo is available
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether redo is available
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Description of the next undo operation
    var undoDescription: String? {
        undoStack.last?.description
    }

    /// Description of the next redo operation
    var redoDescription: String? {
        redoStack.last?.description
    }

    /// Execute a command and add it to the undo stack
    @MainActor
    func execute(_ command: Command) throws {
        try command.execute()
        undoStack.append(command)

        // Trim stack if it exceeds max size
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }

        // Clear redo stack when new command is executed
        redoStack.removeAll()
    }

    /// Undo the last command
    @MainActor
    func undo() throws {
        guard let command = undoStack.popLast() else {
            throw UndoRedoError.noCommandToUndo
        }

        try command.undo()
        redoStack.append(command)
    }

    /// Redo the last undone command
    @MainActor
    func redo() throws {
        guard let command = redoStack.popLast() else {
            throw UndoRedoError.noCommandToRedo
        }

        try command.execute()
        undoStack.append(command)
    }

    /// Clear all undo/redo history
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Get undo stack size (for debugging/testing)
    var undoCount: Int {
        undoStack.count
    }

    /// Get redo stack size (for debugging/testing)
    var redoCount: Int {
        redoStack.count
    }
}

// MARK: - Errors

enum UndoRedoError: LocalizedError {
    case noCommandToUndo
    case noCommandToRedo
    case commandExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCommandToUndo:
            return "No command to undo"
        case .noCommandToRedo:
            return "No command to redo"
        case .commandExecutionFailed(let message):
            return "Command failed: \(message)"
        }
    }
}

// MARK: - Environment Key

struct UndoRedoManagerKey: EnvironmentKey {
    static let defaultValue = UndoRedoManager()
}

extension EnvironmentValues {
    var undoRedoManager: UndoRedoManager {
        get { self[UndoRedoManagerKey.self] }
        set { self[UndoRedoManagerKey.self] = newValue }
    }
}
