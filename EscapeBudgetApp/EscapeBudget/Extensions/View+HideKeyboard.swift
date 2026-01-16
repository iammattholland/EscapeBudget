import SwiftUI

extension View {
    /// Adds a tap gesture to dismiss the keyboard when tapping outside text fields
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }

    /// Hides the keyboard programmatically
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// A custom background view that dismisses keyboard on tap
struct DismissKeyboardOnTapBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                    }
            )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Adds a tap gesture to the background that dismisses the keyboard
    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(DismissKeyboardOnTapBackground())
    }
}
