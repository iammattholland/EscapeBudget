import SwiftUI

/// View modifier that adds undo/redo controls to the toolbar
struct UndoRedoToolbarModifier: ViewModifier {
    @Environment(\.undoRedoManager) private var undoRedoManager
    @State private var showingUndoAlert = false
    @State private var showingRedoAlert = false
    @State private var errorMessage = ""

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Undo button
                    Button {
                        performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!undoRedoManager.canUndo)
                    .help(undoRedoManager.undoDescription ?? "Undo")
                    .keyboardShortcut("z", modifiers: .command)

                    // Redo button
                    Button {
                        performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!undoRedoManager.canRedo)
                    .help(undoRedoManager.redoDescription ?? "Redo")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
            }
            .alert("Undo Failed", isPresented: $showingUndoAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Redo Failed", isPresented: $showingRedoAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
    }

    private func performUndo() {
        do {
            try undoRedoManager.undo()
        } catch {
            SecurityLogger.shared.logSecurityError(error, context: "undo_operation")
            errorMessage = "Unable to undo this action. Please try again."
            showingUndoAlert = true
        }
    }

    private func performRedo() {
        do {
            try undoRedoManager.redo()
        } catch {
            SecurityLogger.shared.logSecurityError(error, context: "redo_operation")
            errorMessage = "Unable to redo this action. Please try again."
            showingRedoAlert = true
        }
    }
}

extension View {
    /// Adds undo/redo controls to the toolbar
    func undoRedoToolbar() -> some View {
        modifier(UndoRedoToolbarModifier())
    }
}

/// A standalone view that displays undo/redo status
struct UndoRedoStatusView: View {
    @Environment(\.undoRedoManager) private var undoRedoManager

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            if undoRedoManager.canUndo {
                Label {
                    Text(undoRedoManager.undoDescription ?? "Undo available")
                        .appCaptionText()
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if undoRedoManager.canRedo {
                Label {
                    Text(undoRedoManager.redoDescription ?? "Redo available")
                        .appCaptionText()
                } icon: {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !undoRedoManager.canUndo && !undoRedoManager.canRedo {
                Label {
                    Text("No actions to undo")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(AppTheme.Radius.compact)
    }
}
