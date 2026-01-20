import SwiftUI
import SwiftData

struct BadgesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @StateObject private var badgeService = BadgeService.shared

    private func tint(for role: Badge.TintRole) -> Color {
        switch role {
        case .tint:
            return AppColors.tint(for: appColorMode)
        case .success:
            return AppColors.success(for: appColorMode)
        case .warning:
            return AppColors.warning(for: appColorMode)
        case .purple:
            return .purple
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                ScrollOffsetReader(coordinateSpace: "BadgesView.scroll", id: "BadgesView.scroll")

                streaksCard
                
                Text("Badges")
                    .appSectionTitleText()
                    .padding(.horizontal, AppTheme.Spacing.medium)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.tight) {
                    ForEach(orderedBadges) { badge in
                        BadgeCardView(
                            title: badge.title,
                            subtitle: badge.subtitle,
                            systemImage: badge.systemImage,
                            tint: tint(for: badge.tintRole),
                            isEarned: badgeService.isEarned(badge.id)
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.bottom, AppTheme.Spacing.medium)
            }
            .padding(.top, AppTheme.Spacing.tight)
        }
        .background(Color(.systemGroupedBackground))
        .coordinateSpace(name: "BadgesView.scroll")
        .onAppear {
            badgeService.recordAppBecameActive(modelContext: modelContext)
        }
    }

    private var orderedBadges: [Badge] {
        BadgeService.catalog.sorted { a, b in
            let aEarned = badgeService.isEarned(a.id)
            let bEarned = badgeService.isEarned(b.id)
            if aEarned != bEarned { return aEarned && !bEarned }
            if a.collection != b.collection { return a.collection.rawValue < b.collection.rawValue }
            return a.title < b.title
        }
    }

    private var streaksCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
            HStack {
                Text("Week Streaks")
                    .appSectionTitleText()
                Spacer()
                Text("\(badgeService.weeklyOpenStreak) week\(badgeService.weeklyOpenStreak == 1 ? "" : "s")")
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: AppTheme.Spacing.tight) {
                StreakMetricView(
                    title: "Current",
                    value: badgeService.weeklyOpenStreak,
                    tint: AppColors.warning(for: appColorMode),
                    systemImage: "flame.fill"
                )
                StreakMetricView(
                    title: "Best",
                    value: badgeService.bestWeeklyOpenStreak,
                    tint: AppColors.tint(for: appColorMode),
                    systemImage: "crown.fill"
                )
                StreakMetricView(
                    title: "Imports",
                    value: badgeService.importsCompleted,
                    tint: AppColors.success(for: appColorMode),
                    systemImage: "tray.and.arrow.down.fill"
                )
            }
        }
        .appElevatedCardSurface(padding: 16, stroke: Color.primary.opacity(0.05))
        .padding(.horizontal, AppTheme.Spacing.medium)
    }
}

private struct StreakMetricView: View {
    let title: String
    let value: Int
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: systemImage)
                    .appCaptionText()
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }

            Text("\(value)")
                .appTitleText()
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(AppTheme.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct BadgeCardView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isEarned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isEarned ? 0.18 : 0.08))
                    Image(systemName: systemImage)
                        .foregroundStyle(isEarned ? tint : .secondary)
                }
                .frame(width: 36, height: 36)

                Spacer()

                if isEarned {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .appSecondaryBodyText()
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .appCaptionText()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appElevatedCardSurface(stroke: Color.primary.opacity(0.05))
        .opacity(isEarned ? 1 : 0.75)
    }
}

#Preview {
    BadgesView()
        .modelContainer(for: [Account.self, Transaction.self, SavingsGoal.self, Category.self, CategoryGroup.self, TransactionTag.self, AutoRule.self], inMemory: true)
}
