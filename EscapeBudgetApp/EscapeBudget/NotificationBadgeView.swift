import SwiftUI

struct NotificationBadgeView: View {
            @State private var showingHub = false
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings
    
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
                    .overlay {
                        if settings.isDemoMode {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.orange.opacity(0.85), lineWidth: 3)
                                )
                                .shadow(color: Color.orange.opacity(0.35), radius: 6, x: 0, y: 0)
                        }
                    }
                    .zIndex(0)
                
                if settings.hasNotifications {
                    Circle()
                        .fill(AppDesign.Colors.danger(for: appColorMode))
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
