import SwiftUI

extension View {
    @ViewBuilder
    func solidPresentationBackground(_ color: Color = Color(.systemBackground)) -> some View {
        if #available(iOS 16.4, *) {
            self
                .globalKeyboardDoneToolbar()
                .presentationBackground(color)
        } else {
            self.globalKeyboardDoneToolbar()
        }
    }
}
