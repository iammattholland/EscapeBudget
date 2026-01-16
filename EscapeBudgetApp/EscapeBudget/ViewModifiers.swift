import SwiftUI

extension View {
    func withAppLogo() -> some View {
        self.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NotificationBadgeView()
            }
        }
    }
}
