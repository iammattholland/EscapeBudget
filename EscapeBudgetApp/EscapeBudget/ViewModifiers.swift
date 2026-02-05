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
            .padding(.horizontal, isCompact ? AppDesign.Theme.Spacing.tight : AppDesign.Theme.Spacing.chromePaddingHorizontal)
            .padding(.vertical, isCompact ? AppDesign.Theme.Spacing.chromePaddingVerticalCompact : AppDesign.Theme.Spacing.chromePaddingVertical)
    }

    func topMenuBarStyle(isCompact: Bool = false) -> some View {
        self
            .padding(.top, isCompact ? AppDesign.Theme.Spacing.nano : AppDesign.Theme.Spacing.micro)
            .padding(.bottom, isCompact ? AppDesign.Theme.Spacing.nano : AppDesign.Theme.Spacing.micro)
            .frame(maxWidth: .infinity)
            .appConstrainContentWidth(maxWidth: AppDesign.Theme.Layout.topMenuMaxWidth)
            .appAdaptiveScreenHorizontalPadding()
    }
}

private struct DemoModeToolbarPill: View {
    @Environment(\.demoPillVisible) private var demoPillVisible

    var body: some View {
        DemoModeBanner(isVisible: demoPillVisible)
            .offset(y: -1)
    }
}
