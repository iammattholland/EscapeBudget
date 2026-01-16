import SwiftUI

private struct SuppressGlobalKeyboardDoneToolbarKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var suppressGlobalKeyboardDoneToolbar: Bool {
        get { self[SuppressGlobalKeyboardDoneToolbarKey.self] }
        set { self[SuppressGlobalKeyboardDoneToolbarKey.self] = newValue }
    }
}

extension View {
    func suppressGlobalKeyboardDoneToolbar(_ suppress: Bool = true) -> some View {
        environment(\.suppressGlobalKeyboardDoneToolbar, suppress)
    }
}

private struct GlobalKeyboardDoneToolbarModifier: ViewModifier {
    @Environment(\.suppressGlobalKeyboardDoneToolbar) private var suppressGlobalKeyboardDoneToolbar

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !suppressGlobalKeyboardDoneToolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
#if canImport(UIKit)
                            KeyboardUtilities.dismiss()
#endif
                        }
                    }
                }
            }
    }
}

extension View {
    func globalKeyboardDoneToolbar() -> some View {
        modifier(GlobalKeyboardDoneToolbarModifier())
    }
}

