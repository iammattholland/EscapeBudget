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
- **Layout**: `AppTheme.Layout.*`

Common spacing rules of thumb:
- Screen edges: `AppTheme.Spacing.screenHorizontal` / `AppTheme.Spacing.screenVertical`
- Card internals: `AppTheme.Spacing.cardPadding`
- Gaps between cards/sections: `AppTheme.Spacing.cardGap`

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
- Section headings: `.appSectionTitleText()`
- Primary body copy: `.appBodyText()`
- Secondary body copy/subtitles: `.appSecondaryBodyText()`
- Captions: `.appCaptionText()`

For common “title + subtitle” stacks, prefer:
- `AppSectionHeader(title:subtitle:)`

If you must use `.font(...)` directly (e.g., charts, very specific UI), try to keep it consistent with `AppTheme.Typography` tokens.

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

## Do / Don’t
**Do**
- Use `AppTheme` tokens for spacing/radii/typography.
- Use `.appCardSurface()` / `.appElevatedCardSurface()` for card containers.
- Use `TopChromeTabs` + `.topChromeSegmentedStyle()` for top navigation chrome.
- Use `.appPrimaryCTA()` / `.appSecondaryCTA()` for prominent actions.

**Don’t**
- Introduce new arbitrary corner radii for “standard cards”.
- Mix `.headline`/`.subheadline`/weights ad-hoc for the same UI role across screens.
- Recreate a “card” with `RoundedRectangle(...)` + `.overlay(stroke...)` when a shared surface exists.

## Quick Checklist (PR review)
- Are card containers using `.appCardSurface()` / `.appElevatedCardSurface()`?
- Are top tabs using `TopChromeTabs`?
- Are primary/secondary actions using `.appPrimaryCTA()` / `.appSecondaryCTA()`?
- Are new paddings/radii pulled from `AppTheme`?

## Large Files (Build Speed)
If a view file grows large (SwiftUI type-check time increases quickly), prefer splitting:
- Keep the public view in a small wrapper file (e.g. `ReviewView.swift`, `ImportDataView.swift`).
- Move the heavy implementation into a sibling file (e.g. `EscapeBudget/Review/ReviewComponents.swift`, `EscapeBudget/Import/ImportDataViewImpl.swift`) and/or extensions.
- Move reusable subviews into their own files as they stabilize.
