import SwiftUI

// MARK: - Design System
//
// This file is the SINGLE SOURCE OF TRUTH for all UI styling in Escape Budget.
// Always use these tokens instead of hardcoded values throughout the app.
//
// ## Usage Guidelines
//
// ### Typography
// Use semantic helpers on Text views:
//   Text("Title").appTitleText()           // Screen/section titles
//   Text("Header").appSectionTitleText()   // Card/list section headers
//   Text("Content").appBodyText()          // Primary content text
//   Text("Secondary").appSecondaryBodyText() // Supporting text
//   Text("Small").appCaptionText()         // Labels, metadata
//   Text("Tiny").appFootnoteText()         // Fine print, timestamps
//
// ### Spacing
// Use AppTheme.Spacing tokens for all padding/spacing:
//   .padding(AppTheme.Spacing.medium)      // Standard content padding
//   .padding(.horizontal, AppTheme.Spacing.screenHorizontal)
//   VStack(spacing: AppTheme.Spacing.tight)
//
// ### Icons
// Use icon helpers for SF Symbols:
//   Image(systemName: "star").appIconSmall()   // 20pt - inline icons
//   Image(systemName: "star").appIconMedium()  // 28pt - list row icons
//   Image(systemName: "star").appIconLarge()   // 36pt - card icons
//   Image(systemName: "star").appIconXLarge()  // 48pt - feature icons
//   Image(systemName: "star").appIconHero()    // 64pt - empty states, heroes
//
// ### Corner Radius
// Use AppTheme.Radius tokens:
//   .cornerRadius(AppTheme.Radius.card)    // Cards, modals
//   .cornerRadius(AppTheme.Radius.button)  // Buttons, tags
//   .appCornerRadius(AppTheme.Radius.card) // Convenience modifier
//
// ### Cards & Surfaces
// Use surface modifiers for consistent card styling:
//   .appCardSurface()                      // Standard card background
//   .appElevatedCardSurface()              // Elevated/floating cards
//
// ### Buttons
// Use CTA modifiers for action buttons:
//   Button("Action") { }.appPrimaryCTA()   // Primary actions
//   Button("Action") { }.appSecondaryCTA() // Secondary actions
//
// ### Layout
// Use adaptive modifiers for responsive design:
//   .appAdaptiveScreenPadding()            // Screen edge padding (adapts to device)
//   .appConstrainContentWidth()            // Max width on iPad/Mac
//
// ### Colors
// Use AppColors (defined in AppColors.swift) for semantic colors:
//   AppColors.tint(for: appColorMode)      // Primary accent color
//   AppColors.success(for: appColorMode)   // Positive/income
//   AppColors.warning(for: appColorMode)   // Warnings/uncategorized
//   AppColors.error(for: appColorMode)     // Errors/destructive
//
// ## Adding New Tokens
// 1. Add the token to the appropriate enum below
// 2. Add a semantic helper extension if needed
// 3. Update this documentation
// 4. Migrate existing hardcoded values to use the new token

enum AppTheme {

    // MARK: - Layout
    // Controls max content width and interaction thresholds
    enum Layout {
        /// Max content width on iPad (regular size class)
        static let maxContentWidthRegular: CGFloat = 720
        /// Max content width on Mac
        static let maxContentWidthMac: CGFloat = 820
        /// Max width for top menu chrome (slightly wider than settings default)
        static let topMenuMaxWidth: CGFloat = 640
        /// Scroll offset threshold for compact chrome transitions
        static let scrollCompactThreshold: CGFloat = 12
        /// Minimum drag distance to trigger swipe actions
        static let swipeActionThreshold: CGFloat = 50
    }

    // MARK: - Spacing
    // Use these tokens for all padding, margins, and gaps.
    // Ordered roughly by size for easy selection.
    enum Spacing {
        // Base scale (1-12pt) - fine adjustments
        static let pixel: CGFloat = 1       // Hairline borders, pixel-perfect alignment
        static let hairline: CGFloat = 2    // Minimal separation
        static let nano: CGFloat = 3        // Tight inline spacing
        static let micro: CGFloat = 4       // Icon-to-text gaps, tight lists
        static let xSmall: CGFloat = 6      // Compact element spacing
        static let compact: CGFloat = 8     // Button padding, tight groups
        static let small: CGFloat = 10      // List item internal spacing
        static let tight: CGFloat = 12      // Dense content areas

        // Standard scale (16-24pt) - common use
        static let medium: CGFloat = 16     // Default content spacing
        static let relaxed: CGFloat = 18    // Comfortable breathing room
        static let large: CGFloat = 20      // Section separation
        static let insetLarge: CGFloat = 22 // Card content insets
        static let xLarge: CGFloat = 24     // Major section gaps

        // Large scale (26-60pt) - structural spacing
        static let indentSmall: CGFloat = 26  // Nested content indent
        static let modalVertical: CGFloat = 28 // Modal top/bottom padding
        static let sectionVertical: CGFloat = 30 // Between major sections
        static let xxLarge: CGFloat = 32    // Large structural gaps
        static let indentMedium: CGFloat = 34 // Deeper nesting
        static let topChromeOffset: CGFloat = 34 // Space below floating chrome
        static let emptyState: CGFloat = 40 // Empty state vertical padding
        static let indentXL: CGFloat = 52   // Deep hierarchy indent
        static let hero: CGFloat = 60       // Hero section spacing

        // Screen padding - adapts to device size
        static let screenHorizontal: CGFloat = medium // iPhone horizontal edges
        static let screenVertical: CGFloat = 12       // iPhone vertical edges
        static let screenHorizontalRegular: CGFloat = xLarge // iPad horizontal edges
        static let screenVerticalRegular: CGFloat = medium   // iPad vertical edges

        // Component-specific
        static let cardPadding: CGFloat = 14  // Internal card content padding
        static let cardGap: CGFloat = 14      // Gap between cards
        static let chromePaddingHorizontal: CGFloat = 14 // Floating chrome horizontal
        static let chromePaddingVertical: CGFloat = 12   // Floating chrome vertical
        static let chromePaddingVerticalCompact: CGFloat = 8 // Compact chrome vertical
    }

    // MARK: - Radius
    // Corner radius tokens. Use .continuous style for Apple HIG compliance.
    enum Radius {
        // Small radii (2-8pt) - subtle rounding
        static let hairline: CGFloat = 2   // Barely visible rounding
        static let micro: CGFloat = 3      // Tiny elements
        static let mini: CGFloat = 4       // Small badges, indicators
        static let tag: CGFloat = 6        // Tags, chips
        static let xSmall: CGFloat = 8     // Small buttons, inputs

        // Medium radii (10-18pt) - standard components
        static let button: CGFloat = 10    // Buttons, form controls
        static let compact: CGFloat = 12   // Compact cards, list items
        static let tabsSelection: CGFloat = 12 // Tab selection background
        static let tabsOuter: CGFloat = 14 // Tab bar container
        static let small: CGFloat = 14     // Small cards
        static let overlay: CGFloat = 16   // Overlays, tooltips
        static let card: CGFloat = 18      // Standard cards (primary)
        static let medium: CGFloat = 18    // Alias for card
        static let chromeCompact: CGFloat = 18 // Compact floating chrome

        // Large radii (20-28pt) - prominent elements
        static let large: CGFloat = 20     // Large cards
        static let chrome: CGFloat = 22    // Floating chrome bars
        static let pill: CGFloat = 24      // Pill-shaped elements
        static let hero: CGFloat = 26      // Hero cards, modals
        static let pillLarge: CGFloat = 28 // Large pill buttons
    }

    // MARK: - Stroke
    // Border and divider styling
    enum Stroke {
        static let subtle: CGFloat = 1        // Standard border width
        static let subtleOpacity: Double = 0.06 // Subtle border opacity
    }

    // MARK: - Icon Size
    // SF Symbol sizing. Use appIcon*() helpers for convenience.
    enum IconSize {
        static let small: CGFloat = 20      // Inline icons, list accessories
        static let medium: CGFloat = 28     // List row leading icons
        static let large: CGFloat = 36      // Card icons, EmptyDataCard
        static let xLarge: CGFloat = 48     // Feature callouts, onboarding
        static let emptyState: CGFloat = 50 // Empty state illustrations
        static let hero: CGFloat = 64       // Hero sections, large empty states
    }

    // MARK: - Typography
    // Font definitions. Use appXxxText() helpers for convenience.
    // All fonts use system dynamic type for accessibility.
    enum Typography {
        /// Screen titles, modal headers - .title3.semibold
        static let title: Font = .title3.weight(.semibold)
        /// Section headers, card titles - .headline.semibold
        static let sectionTitle: Font = .headline.weight(.semibold)
        /// Primary content text - .body
        static let body: Font = .body
        /// Supporting text, descriptions - .subheadline
        static let secondaryBody: Font = .subheadline
        /// Small labels, metadata - .caption
        static let caption: Font = .caption
        /// Fine print, timestamps - .footnote
        static let footnote: Font = .footnote
        /// Emphasized small text - .caption.semibold
        static let captionStrong: Font = .caption.weight(.semibold)
        /// Tab bar labels - .subheadline.semibold
        static let tabLabel: Font = .subheadline.weight(.semibold)
        /// Button text - .headline
        static let buttonLabel: Font = .headline
    }
}

// MARK: - View Extensions
// Semantic helpers that apply design system tokens consistently.
// Prefer these over direct token access for common patterns.

extension View {

    // MARK: Backgrounds & Surfaces

    /// Applies the standard screen background color (systemGroupedBackground)
    func appScreenBackground() -> some View {
        self.background(Color(.systemGroupedBackground))
    }

    /// Standard card surface with subtle border. Use for content cards in lists.
    /// - Parameters:
    ///   - padding: Internal padding (default: cardPadding)
    ///   - fill: Background color (default: secondarySystemGroupedBackground)
    ///   - stroke: Border color (default: subtle primary)
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

    /// Elevated card surface for floating/prominent cards.
    /// Uses .background fill for a lifted appearance.
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

    // MARK: Button Styling

    /// Full-width button label styling (for custom button content)
    func appPrimaryButtonLabel() -> some View {
        self
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    /// Full-width secondary button label styling
    func appSecondaryButtonLabel() -> some View {
        self
            .font(AppTheme.Typography.buttonLabel.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    /// Primary call-to-action button style (borderedProminent).
    /// Use for the main action in a view.
    /// Example: Button("Save") { }.appPrimaryCTA()
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

    /// Secondary call-to-action button style (bordered).
    /// Use for alternative/cancel actions.
    /// Example: Button("Cancel") { }.appSecondaryCTA()
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

    // MARK: Typography Helpers

    /// Section/card headers - .headline.semibold
    func appSectionTitleText() -> some View {
        self.font(AppTheme.Typography.sectionTitle)
    }

    /// Primary content text - .body
    func appBodyText() -> some View {
        self.font(AppTheme.Typography.body)
    }

    /// Supporting/secondary text - .subheadline
    func appSecondaryBodyText() -> some View {
        self.font(AppTheme.Typography.secondaryBody)
    }

    /// Small labels, metadata - .caption
    func appCaptionText() -> some View {
        self.font(AppTheme.Typography.caption)
    }

    /// Screen/modal titles - .title3.semibold
    func appTitleText() -> some View {
        self.font(AppTheme.Typography.title)
    }

    /// Fine print, timestamps - .footnote
    func appFootnoteText() -> some View {
        self.font(AppTheme.Typography.footnote)
    }

    // MARK: Layout Helpers

    /// Constrains content to max width on iPad/Mac for readability.
    /// Content is centered when constrained.
    func appConstrainContentWidth(maxWidth: CGFloat = AppTheme.Layout.maxContentWidthRegular) -> some View {
        self.modifier(AppConstrainContentWidthModifier(maxWidth: maxWidth))
    }

    /// Applies adaptive screen padding (horizontal + vertical).
    /// Uses larger padding on iPad, standard on iPhone.
    func appAdaptiveScreenPadding() -> some View {
        self.modifier(AppAdaptiveScreenPaddingModifier())
    }

    /// Applies only horizontal screen padding (adapts to device).
    func appAdaptiveScreenHorizontalPadding() -> some View {
        self.modifier(AppAdaptiveScreenHorizontalPaddingModifier())
    }

    func appLightModePageBackground() -> some View {
        self.modifier(AppLightModePageBackgroundModifier())
    }

    // MARK: Icon Helpers

    /// Custom icon size - use sparingly, prefer named sizes
    func appIcon(size: CGFloat) -> some View {
        self.font(.system(size: size))
    }

    /// Small icon (20pt) - inline icons, list accessories
    func appIconSmall() -> some View {
        self.font(.system(size: AppTheme.IconSize.small))
    }

    /// Medium icon (28pt) - list row leading icons
    func appIconMedium() -> some View {
        self.font(.system(size: AppTheme.IconSize.medium))
    }

    /// Large icon (36pt) - card icons, empty states
    func appIconLarge() -> some View {
        self.font(.system(size: AppTheme.IconSize.large))
    }

    /// Extra large icon (48pt) - feature callouts
    func appIconXLarge() -> some View {
        self.font(.system(size: AppTheme.IconSize.xLarge))
    }

    /// Hero icon (64pt) - large empty states, onboarding
    func appIconHero() -> some View {
        self.font(.system(size: AppTheme.IconSize.hero))
    }

    // MARK: Shape Helpers

    /// Convenience for rounded rectangle clip shape.
    /// Uses .continuous style by default for Apple HIG compliance.
    func appCornerRadius(_ radius: CGFloat, style: RoundedCornerStyle = .continuous) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: style))
    }
}

private struct AppLightModePageBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(colorScheme == .dark ? Color.clear : Color(.systemGroupedBackground))
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
