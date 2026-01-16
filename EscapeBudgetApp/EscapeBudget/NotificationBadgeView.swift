import SwiftUI

struct NotificationBadgeView: View {
    @AppStorage("hasNotifications") var hasNotifications = false
    @State private var showingHub = false
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        Button(action: {
            showingHub = true
        }) {
            ZStack(alignment: .topTrailing) {
                Image("RocketLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .zIndex(0)
                
                if hasNotifications {
                    Circle()
                        .fill(AppColors.danger(for: appColorMode))
                        .frame(width: 10, height: 10)
                        // Keep the badge fully inside the toolbar hit-area to avoid clipping.
                        .offset(x: -1, y: 1)
                        .zIndex(1)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingHub) {
            NotificationsSettingsHubView()
        }
    }
}

#Preview {
    NotificationBadgeView()
}
