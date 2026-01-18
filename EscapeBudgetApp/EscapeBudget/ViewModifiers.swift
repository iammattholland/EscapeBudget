import SwiftUI

private struct DemoPillVisibilityKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var demoPillVisible: Bool {
        get { self[DemoPillVisibilityKey.self] }
        set { self[DemoPillVisibilityKey.self] = newValue }
    }
}

extension View {
    func withAppLogo() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NotificationBadgeView()
                }
                ToolbarItem(placement: .principal) {
                    DemoModeToolbarPill()
                }
            }
    }

    func topChromeSegmentedStyle(isCompact: Bool = false) -> some View {
        self
            .padding(.horizontal, isCompact ? 12 : 14)
            .padding(.vertical, isCompact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 18 : 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 18 : 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct DemoModeToolbarPill: View {
    @Environment(\.demoPillVisible) private var demoPillVisible

    var body: some View {
        DemoModeBanner(isVisible: demoPillVisible)
            .offset(y: -1)
    }
}
