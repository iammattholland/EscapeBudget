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
            .padding(.horizontal, isCompact ? AppTheme.Spacing.tight : AppTheme.Spacing.chromePaddingHorizontal)
            .padding(.vertical, isCompact ? AppTheme.Spacing.chromePaddingVerticalCompact : AppTheme.Spacing.chromePaddingVertical)
    }

    func topMenuBarStyle(isCompact: Bool = false) -> some View {
        self
            .padding(.top, isCompact ? AppTheme.Spacing.nano : AppTheme.Spacing.micro)
            .padding(.bottom, isCompact ? AppTheme.Spacing.nano : AppTheme.Spacing.micro)
            .frame(maxWidth: AppTheme.Layout.topMenuMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: AppTheme.Stroke.subtle)
            )
            .padding(.horizontal, AppTheme.Spacing.screenHorizontal)
            .frame(maxWidth: .infinity)
    }
}

private struct DemoModeToolbarPill: View {
    @Environment(\.demoPillVisible) private var demoPillVisible

    var body: some View {
        DemoModeBanner(isVisible: demoPillVisible)
            .offset(y: -1)
    }
}
