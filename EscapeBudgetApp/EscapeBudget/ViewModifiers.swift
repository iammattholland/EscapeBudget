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
            .padding(.horizontal, isCompact ? 12 : AppTheme.Spacing.chromePaddingHorizontal)
            .padding(.vertical, isCompact ? AppTheme.Spacing.chromePaddingVerticalCompact : AppTheme.Spacing.chromePaddingVertical)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppTheme.Stroke.subtleOpacity), lineWidth: AppTheme.Stroke.subtle)
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
