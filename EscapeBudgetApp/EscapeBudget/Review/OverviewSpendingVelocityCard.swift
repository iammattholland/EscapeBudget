import SwiftUI

/// Home screen card displaying spending velocity indicator
struct OverviewSpendingVelocityCard: View {
    let velocityData: SpendingVelocityData
    let currencyCode: String

    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Computed Properties

    private var gaugeSize: CGFloat {
        horizontalSizeClass == .regular ? 64 : 54
    }

    private var statusColor: Color {
        switch velocityData.status {
        case .underPace, .noSpending:
            return AppDesign.Colors.success(for: appColorMode)
        case .onPace:
            return AppDesign.Colors.warning(for: appColorMode)
        case .slightlyOver, .overPace:
            return AppDesign.Colors.danger(for: appColorMode)
        case .noBudget:
            return .secondary
        }
    }

    private var projectionText: String {
        guard velocityData.budgetAssigned > 0 else {
            return "Set a budget to see projections"
        }

        if velocityData.isPeriodComplete {
            if velocityData.projectedRemainingBudget >= 0 {
                return "Finished \(velocityData.projectedRemainingBudget.formatted(.currency(code: currencyCode))) under budget"
            } else {
                return "Finished \(velocityData.projectedOverBudget.formatted(.currency(code: currencyCode))) over budget"
            }
        }

        if velocityData.projectedRemainingBudget >= 0 {
            return "On track to have \(velocityData.projectedRemainingBudget.formatted(.currency(code: currencyCode))) remaining"
        } else {
            return "Projected to exceed budget by \(velocityData.projectedOverBudget.formatted(.currency(code: currencyCode)))"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.cardGap) {
            // Header with gauge
            HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.tight) {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    Text("Spending Pace")
                        .appSectionTitleText()

                    Text(velocityData.statusLabel)
                        .appSecondaryBodyText()
                        .foregroundStyle(statusColor)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(spacing: AppDesign.Theme.Spacing.micro) {
                    SpendingVelocityGauge(
                        velocityRatio: velocityData.velocityRatio,
                        size: gaugeSize
                    )

                    Text(velocityRatioText)
                        .appCaptionText()
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Metrics grid
            if velocityData.isUsable {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppDesign.Theme.Spacing.small),
                        GridItem(.flexible(), spacing: AppDesign.Theme.Spacing.small)
                    ],
                    spacing: AppDesign.Theme.Spacing.small
                ) {
                    OverviewValueTile(
                        title: "Daily Spend",
                        value: velocityData.dailyVelocity,
                        currencyCode: currencyCode,
                        tint: .primary
                    )
                    OverviewValueTile(
                        title: "Target / Day",
                        value: velocityData.targetDailyVelocity,
                        currencyCode: currencyCode,
                        tint: .secondary
                    )
                }

                // Period progress meter
                OverviewInlineMeter(
                    title: "Period Progress",
                    valueText: "Day \(velocityData.daysElapsed) of \(velocityData.daysInPeriod)",
                    progress: velocityData.periodProgress,
                    tint: AppDesign.Colors.tint(for: appColorMode)
                )

                // Projection summary
                HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                    Image(systemName: projectionIcon)
                        .foregroundStyle(projectionColor)
                        .appIconSmall()

                    Text(projectionText)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if velocityData.status == .noBudget {
                // No budget state
                ContentUnavailableView(
                    "No Budget Set",
                    systemImage: "gauge.with.dots.needle.0percent",
                    description: Text("Assign budget amounts to categories to track your spending pace.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
            } else {
                // No spending state
                ContentUnavailableView(
                    "No Spending Yet",
                    systemImage: "gauge.with.dots.needle.0percent",
                    description: Text("Start adding transactions to see your spending pace.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spending Pace")
    }

    // MARK: - Helpers

    private var velocityRatioText: String {
        if velocityData.status == .noBudget {
            return "—"
        }
        if velocityData.velocityRatio >= 2 {
            return "2x+"
        }
        return String(format: "%.1fx", velocityData.velocityRatio)
    }

    private var projectionIcon: String {
        if velocityData.projectedRemainingBudget >= 0 {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }

    private var projectionColor: Color {
        if velocityData.projectedRemainingBudget >= 0 {
            return AppDesign.Colors.success(for: appColorMode)
        } else {
            return AppDesign.Colors.danger(for: appColorMode)
        }
    }
}

// MARK: - Previews

#Preview("On Track") {
    let data = SpendingVelocityData(
        periodStart: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(),
        periodEnd: Calendar.current.date(byAdding: .day, value: 16, to: Date()) ?? Date(),
        daysInPeriod: 31,
        daysElapsed: 15,
        actualSpent: 1500,
        budgetAssigned: 3000
    )

    ScrollView {
        OverviewSpendingVelocityCard(velocityData: data, currencyCode: "USD")
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(AppDesign.Theme.Radius.card)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Over Pace") {
    let data = SpendingVelocityData(
        periodStart: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
        periodEnd: Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date(),
        daysInPeriod: 31,
        daysElapsed: 11,
        actualSpent: 2000,
        budgetAssigned: 3000
    )

    ScrollView {
        OverviewSpendingVelocityCard(velocityData: data, currencyCode: "USD")
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(AppDesign.Theme.Radius.card)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("No Budget") {
    let data = SpendingVelocityData(
        periodStart: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
        periodEnd: Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date(),
        daysInPeriod: 31,
        daysElapsed: 11,
        actualSpent: 500,
        budgetAssigned: 0
    )

    ScrollView {
        OverviewSpendingVelocityCard(velocityData: data, currencyCode: "USD")
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(AppDesign.Theme.Radius.card)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
