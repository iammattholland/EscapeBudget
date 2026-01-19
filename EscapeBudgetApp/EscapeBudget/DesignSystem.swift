import SwiftUI

enum AppTheme {
    enum Layout {
        static let maxContentWidthRegular: CGFloat = 720
        static let maxContentWidthMac: CGFloat = 820
    }

    enum Spacing {
        static let xSmall: CGFloat = 6
        static let compact: CGFloat = 8
        static let small: CGFloat = 10
        static let tight: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let screenHorizontal: CGFloat = 16
        static let screenVertical: CGFloat = 12

        static let screenHorizontalRegular: CGFloat = 24
        static let screenVerticalRegular: CGFloat = 16

        static let cardPadding: CGFloat = 14
        static let cardGap: CGFloat = 14

        static let chromePaddingHorizontal: CGFloat = 14
        static let chromePaddingVertical: CGFloat = 12
        static let chromePaddingVerticalCompact: CGFloat = 8
    }

    enum Radius {
        static let xSmall: CGFloat = 8
        static let compact: CGFloat = 12
        static let small: CGFloat = 14
        static let card: CGFloat = 18
        static let large: CGFloat = 20
        static let medium: CGFloat = 18
        static let chrome: CGFloat = 22
        static let chromeCompact: CGFloat = 18
        static let pill: CGFloat = 24
        static let hero: CGFloat = 26
        static let pillLarge: CGFloat = 28
        static let overlay: CGFloat = 16

        static let tabsOuter: CGFloat = 14
        static let tabsSelection: CGFloat = 12
        static let button: CGFloat = 10
    }

    enum Stroke {
        static let subtle: CGFloat = 1
        static let subtleOpacity: Double = 0.06
    }

    enum Typography {
        static let title: Font = .title3.weight(.semibold)
        static let sectionTitle: Font = .headline.weight(.semibold)
        static let body: Font = .body
        static let secondaryBody: Font = .subheadline
        static let caption: Font = .caption
        static let footnote: Font = .footnote
        static let captionStrong: Font = .caption.weight(.semibold)
        static let tabLabel: Font = .subheadline.weight(.semibold)
        static let buttonLabel: Font = .headline
    }
}

extension View {
    func appScreenBackground() -> some View {
        self.background(Color(.systemGroupedBackground))
    }

    func appCardSurface(
        padding: CGFloat = AppTheme.Spacing.cardPadding,
        fill: Color = Color(.secondarySystemGroupedBackground),
        stroke: Color = Color.primary.opacity(AppTheme.Stroke.subtleOpacity)
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .strokeBorder(stroke, lineWidth: AppTheme.Stroke.subtle)
            )
    }

    func appElevatedCardSurface(
        padding: CGFloat = AppTheme.Spacing.cardPadding,
        stroke: Color = Color(.separator).opacity(0.35)
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(stroke)
            )
    }

    func appPrimaryButtonLabel() -> some View {
        self
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    func appSecondaryButtonLabel() -> some View {
        self
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func appPrimaryCTA(controlSize: ControlSize? = nil) -> some View {
        let styled = self
            .buttonStyle(.borderedProminent)
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))

        if let controlSize {
            styled.controlSize(controlSize)
        } else {
            styled
        }
    }

    @ViewBuilder
    func appSecondaryCTA(controlSize: ControlSize? = nil) -> some View {
        let styled = self
            .buttonStyle(.bordered)
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))

        if let controlSize {
            styled.controlSize(controlSize)
        } else {
            styled
        }
    }

    func appSectionTitleText() -> some View {
        self.font(AppTheme.Typography.sectionTitle)
    }

    func appBodyText() -> some View {
        self.font(AppTheme.Typography.body)
    }

    func appSecondaryBodyText() -> some View {
        self.font(AppTheme.Typography.secondaryBody)
    }

    func appCaptionText() -> some View {
        self.font(AppTheme.Typography.caption)
    }

    func appConstrainContentWidth(maxWidth: CGFloat = AppTheme.Layout.maxContentWidthRegular) -> some View {
        self.modifier(AppConstrainContentWidthModifier(maxWidth: maxWidth))
    }

    func appAdaptiveScreenPadding() -> some View {
        self.modifier(AppAdaptiveScreenPaddingModifier())
    }

    func appAdaptiveScreenHorizontalPadding() -> some View {
        self.modifier(AppAdaptiveScreenHorizontalPaddingModifier())
    }
}

private struct AppConstrainContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat

    #if os(macOS)
    private var shouldConstrain: Bool { true }
    private var activeMaxWidth: CGFloat { AppTheme.Layout.maxContentWidthMac }
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var shouldConstrain: Bool { horizontalSizeClass == .regular }
    private var activeMaxWidth: CGFloat { maxWidth }
    #endif

    func body(content: Content) -> some View {
        if shouldConstrain {
            content
                .frame(maxWidth: activeMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}

private struct AppAdaptiveScreenPaddingModifier: ViewModifier {
    #if os(macOS)
    private var hPadding: CGFloat { AppTheme.Spacing.screenHorizontalRegular }
    private var vPadding: CGFloat { AppTheme.Spacing.screenVerticalRegular }
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var hPadding: CGFloat {
        horizontalSizeClass == .regular ? AppTheme.Spacing.screenHorizontalRegular : AppTheme.Spacing.screenHorizontal
    }
    private var vPadding: CGFloat {
        horizontalSizeClass == .regular ? AppTheme.Spacing.screenVerticalRegular : AppTheme.Spacing.screenVertical
    }
    #endif

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
    }
}

private struct AppAdaptiveScreenHorizontalPaddingModifier: ViewModifier {
    #if os(macOS)
    private var hPadding: CGFloat { AppTheme.Spacing.screenHorizontalRegular }
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var hPadding: CGFloat {
        horizontalSizeClass == .regular ? AppTheme.Spacing.screenHorizontalRegular : AppTheme.Spacing.screenHorizontal
    }
    #endif

    func body(content: Content) -> some View {
        content.padding(.horizontal, hPadding)
    }
}
