# Performance Measuring (Escape Budget)

This repo includes lightweight signposts so you can measure real-world performance in Instruments without changing functionality.

## Runtime (Instruments)

1. Xcode → **Product** → **Profile**.
2. Choose **Points of Interest** (and optionally add **Time Profiler** + **Energy Log**).
3. Run the flows you care about (launch, switching tabs, Review screen, imports, etc.).
4. In the **Points of Interest** timeline, filter to subsystem `com.mattholland.EscapeBudget` and category `performance`.

### Included signposts/events

- Intervals:
  - `StatsUpdate.refresh`
  - `MonthlyAccountTotals.ensureUpToDateAsync`
  - `MonthlyAccountTotals.rebuildAllAsync`
  - `MonthlyAccountTotals.applyDirtyAccountMonthKeys`
  - `MonthlyCashflow.ensureUpToDateAsync`
  - `MonthlyCashflow.rebuildAllAsync`
  - `MonthlyCashflow.applyDirtyMonthKeys`
  - `AutoBackup.maybeRunWeekly`
  - `AutoBackup.runNow`
  - `Review.recomputeAccountBalances`
  - `Review.recomputeAccountBalances.fetchRemainder`
- Events:
  - `DataChangeTracker.bump`

If you see a signpost interval repeating rapidly while the UI is idle, that’s a strong hint of a “hot loop” (often caused by expensive work being retriggered by view updates).

## Build time (CLI)

To see where build time is going, run:

`xcodebuild -project EscapeBudget.xcodeproj -scheme EscapeBudget -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath ./DerivedDataPerf build -showBuildTimingSummary`

Notes:
- In this project, Swift compilation dominates overall time. Large SwiftUI view files tend to be the biggest incremental-build offenders.
- Keeping `-derivedDataPath` inside the repo can avoid occasional global DerivedData build-db issues.

