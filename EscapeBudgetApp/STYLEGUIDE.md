# Escape Budget UI Style Guide

This project uses a small, code-first design system to keep spacing, typography, radii, and common surfaces consistent across the app.

Primary source of truth:
- `EscapeBudget/DesignSystem.swift` (`AppTheme` + shared view modifiers)
- `EscapeBudget/ViewModifiers.swift` (`topChromeSegmentedStyle`, `withAppLogo`)
- `EscapeBudget/Components/TopChromeTabs.swift`

Secondary (performance + organization):
- `PERFORMANCE.md` (Instruments signposts)
- `BUILDING.md` (build speed tips + large-file strategy)

## Goals
- Consistent “feel” across all screens (fonts, padding, corner radius, borders).
- Fewer one-off `padding(...)`, `cornerRadius(...)`, `font(...)` decisions sprinkled around.
- Easy to evolve styles by changing tokens in one place.

## Tokens (Design Tokens)
Use tokens from `AppTheme` instead of hard-coded values.

- **Typography**: `AppTheme.Typography.*`
- **Spacing**: `AppTheme.Spacing.*`
- **Radius**: `AppTheme.Radius.*`
- **Stroke**: `AppTheme.Stroke.*`
- **IconSize**: `AppTheme.IconSize.*`
- **Layout**: `AppTheme.Layout.*`

### Spacing Scale
Prefer these tokens instead of numeric `padding(...)` / `spacing:` values.

- `AppTheme.Spacing.pixel` (1): tiny icon nudges/alignment fixes only
- `AppTheme.Spacing.hairline` (2): dividers/progress details
- `AppTheme.Spacing.nano` (3): dense label stacks (rare)
- `AppTheme.Spacing.micro` (4): compact row internals
- `AppTheme.Spacing.xSmall` (6)
- `AppTheme.Spacing.compact` (8)
- `AppTheme.Spacing.small` (10)
- `AppTheme.Spacing.tight` (12)
- `AppTheme.Spacing.medium` (16)
- `AppTheme.Spacing.relaxed` (18)
- `AppTheme.Spacing.large` (20)
- `AppTheme.Spacing.xLarge` (24)
- `AppTheme.Spacing.xxLarge` (32)

App-specific layout tokens (use to preserve established layouts):
- `AppTheme.Spacing.cardPadding` (14), `AppTheme.Spacing.cardGap` (14)
- `AppTheme.Spacing.screenHorizontal` (16), `AppTheme.Spacing.screenVertical` (12)
- `AppTheme.Spacing.screenHorizontalRegular` (24), `AppTheme.Spacing.screenVerticalRegular` (16)
- `AppTheme.Spacing.topChromeOffset` (34)
- `AppTheme.Spacing.indentSmall` (26), `AppTheme.Spacing.indentMedium` (34), `AppTheme.Spacing.indentXL` (52)
- `AppTheme.Spacing.insetLarge` (22)
- `AppTheme.Spacing.sectionVertical` (30)
- `AppTheme.Spacing.modalVertical` (28)
- `AppTheme.Spacing.emptyState` (40)
- `AppTheme.Spacing.hero` (60)

### Layout Constants
- `AppTheme.Layout.scrollCompactThreshold` (12): when headers switch to “compact” as you scroll
- `AppTheme.Layout.swipeActionThreshold` (50): horizontal swipe distance used for month navigation

Common spacing rules of thumb:
- Screen edges: `AppTheme.Spacing.screenHorizontal` / `AppTheme.Spacing.screenVertical`
- Card internals: `AppTheme.Spacing.cardPadding`
- Gaps between cards/sections: `AppTheme.Spacing.cardGap`

## Colors
- Prefer `.foregroundStyle(...)` and `.background(...)` with semantic styles over `.foregroundColor(...)`.
- For app-tinted semantic colors that respect `AppColorMode`, use `AppColors.*(for: appColorMode)` (tint/success/warning/danger).

## Common Surfaces
Prefer these modifiers instead of manually building a rounded background + stroke.

- **Grouped card (system grouped background)**
  - Use: `.appCardSurface()`
  - Typical for: analytics/report cards, grouped list-like cards, “tile” content on grouped backgrounds.

- **Elevated card (system background)**
  - Use: `.appElevatedCardSurface()`
  - Typical for: tiles sitting on a grouped background that should look “raised”.

Notes:
- Standard card rounding uses `AppTheme.Radius.card` (currently 18).
- Small chips/pills commonly use `AppTheme.Radius.small` (14).

If you need a custom fill/stroke but still want consistent radius + framing:
- `.appCardSurface(padding:..., fill:..., stroke:...)`

## Top Chrome (Tabs / Filters / Search)
For top segmented chrome, use the existing chrome style:
- `.topChromeSegmentedStyle(isCompact: ...)`

For top tab switching:
- Use `TopChromeTabs` (don’t build new custom tab rows).

## Buttons (CTAs)
To keep button typography consistent:
- Primary CTA: `.appPrimaryCTA()`
- Secondary CTA: `.appSecondaryCTA()`

If you need to force a control size:
- `.appPrimaryCTA(controlSize: .large)`
- `.appSecondaryCTA(controlSize: .small)`

Button label helpers (useful when the label is a custom `VStack`/`HStack`):
- `.appPrimaryButtonLabel()`
- `.appSecondaryButtonLabel()`

## Typography
Prefer semantic text helpers over raw `.font(...)` when the text is playing a common role:
- Screen/modal titles: `.appTitleText()` (.title3.semibold)
- Section headings: `.appSectionTitleText()` (.headline.semibold)
- Primary body copy: `.appBodyText()` (.body)
- Secondary body copy/subtitles: `.appSecondaryBodyText()` (.subheadline)
- Captions/labels: `.appCaptionText()` (.caption)
- Fine print/timestamps: `.appFootnoteText()` (.footnote)

For common "title + subtitle" stacks, prefer:
- `AppSectionHeader(title:subtitle:)`

If you must use `.font(...)` directly (e.g., charts, very specific UI), try to keep it consistent with `AppTheme.Typography` tokens.

## Icons (SF Symbols)
Use icon size helpers instead of raw `.font(.system(size: ...))`:
- Inline/accessories: `.appIconSmall()` (20pt)
- List row icons: `.appIconMedium()` (28pt)
- Card icons: `.appIconLarge()` (36pt)
- Feature callouts: `.appIconXLarge()` (48pt)
- Hero/empty states: `.appIconHero()` (64pt)

For custom sizes (use sparingly): `.appIcon(size: CGFloat)`

Icon size tokens are also available directly: `AppTheme.IconSize.small`, `.medium`, `.large`, `.xLarge`, `.hero`, `.emptyState`

## Responsive Layout (iPhone / iPad / Mac)
Avoid hard-coding “iPhone-ish” paddings/widths. Prefer these helpers:
- `.appConstrainContentWidth()` to keep content readable on iPad/Mac (centers and caps width).
- `.appAdaptiveScreenPadding()` for screen padding that scales up on iPad/Mac.
- `.appAdaptiveScreenHorizontalPadding()` when you only want adaptive horizontal insets (e.g., top chrome in `safeAreaInset`).

Rules of thumb:
- Top chrome rows should use adaptive horizontal padding (don’t pin to 16 on iPad).
- Scroll content should be constrained + padded for readability on large screens.

## Empty / No Data States
Use `EmptyDataCard(...)` for empty states so icon sizing, spacing, and action styling stay consistent.

```swift
// With action button
EmptyDataCard(
    systemImage: "tray",
    title: "No Items",
    message: "Add your first item to get started.",
    actionTitle: "Add Item",
    action: { showAddSheet = true }
)

// Without action button (actionTitle defaults to empty)
EmptyDataCard(
    systemImage: "checkmark.circle.fill",
    title: "All Done",
    message: "You've completed all tasks."
)
```

## Corner Radius
Use `AppTheme.Radius` tokens for consistent rounding:
- Buttons/inputs: `.button` (10pt)
- Compact cards: `.compact` (12pt)
- Standard cards: `.card` (18pt)
- Floating chrome: `.chrome` (22pt)
- Pills/badges: `.pill` (24pt)

Convenience modifier: `.appCornerRadius(AppTheme.Radius.card)`

## Do / Don't
**Do**
- Use `AppTheme` tokens for spacing/radii/typography/icons.
- Use `.appCardSurface()` / `.appElevatedCardSurface()` for card containers.
- Use `TopChromeTabs` + `.topChromeSegmentedStyle()` for top navigation chrome.
- Use `.appPrimaryCTA()` / `.appSecondaryCTA()` for prominent actions.
- Use `.appTitleText()`, `.appSectionTitleText()`, etc. for text styling.
- Use `.appIconSmall()`, `.appIconLarge()`, etc. for SF Symbol sizing.
- Use `EmptyDataCard` for empty/no-data states.
- Use `AppColors.*(for: appColorMode)` for semantic colors.

**Don't**
- Hardcode font sizes (`.font(.system(size: 24))`) - use typography tokens.
- Hardcode icon sizes (`.font(.system(size: 48))`) - use icon helpers.
- Hardcode spacing values (`.padding(16)`) - use spacing tokens.
- Introduce new arbitrary corner radii for "standard cards".
- Mix `.headline`/`.subheadline`/weights ad-hoc for the same UI role across screens.
- Recreate a "card" with `RoundedRectangle(...)` + `.overlay(stroke...)` when a shared surface exists.
- Build inline empty states when `EmptyDataCard` fits the use case.

## Quick Checklist (PR review)
- Are card containers using `.appCardSurface()` / `.appElevatedCardSurface()`?
- Are top tabs using `TopChromeTabs`?
- Are primary/secondary actions using `.appPrimaryCTA()` / `.appSecondaryCTA()`?
- Are new paddings/radii pulled from `AppTheme`?
- Are text styles using `.appTitleText()`, `.appSectionTitleText()`, etc.?
- Are icon sizes using `.appIconSmall()`, `.appIconLarge()`, etc.?
- Are empty states using `EmptyDataCard`?
- Are semantic colors using `AppColors`?

## Large Files (Build Speed)
If a view file grows large (SwiftUI type-check time increases quickly), prefer splitting:
- Keep the public view in a small wrapper file (e.g. `ReviewView.swift`, `ImportDataView.swift`).
- Move the heavy implementation into a sibling file (e.g. `EscapeBudget/Review/ReviewComponents.swift`, `EscapeBudget/Import/ImportDataViewImpl.swift`) and/or extensions.
- Move reusable subviews into their own files as they stabilize.
