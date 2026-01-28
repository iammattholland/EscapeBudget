import SwiftUI

struct ToolsView: View {
    @State private var demoPillVisible = true

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollOffsetReader(coordinateSpace: "ToolsView.scroll", id: "ToolsView.scroll")

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Available Now")
                            .appSectionTitleText()

                        VStack(spacing: AppTheme.Spacing.cardGap) {
                            NavigationLink {
                                SpendingChallengesView()
                            } label: {
                                ToolCard(
                                    title: "Spending Challenges",
                                    subtitle: "Build better habits with verifiable goals tracked by your transactions."
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                YearEndReviewView()
                            } label: {
                                ToolCard(
                                    title: "Year End Review",
                                    subtitle: "A Spotify‑wrapped style recap with highlights, trends, and insights."
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                DebtPayoffPlannerView()
                            } label: {
                                ToolCard(
                                    title: "Debt Payoff Planner",
                                    subtitle: "Build payoff plans, compare strategies, and track progress toward zero."
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                BillsDashboardView()
                            } label: {
                                ToolCard(
                                    title: "Bills Dashboard",
                                    subtitle: "An overview of your repeating monthly bills with due dates, totals, and trends."
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Planned Features")
                            .appSectionTitleText()

                        VStack(spacing: AppTheme.Spacing.cardGap) {
                            ToolCard(
                                title: "Receipt Scanner",
                                subtitle: "Capture receipts and auto-extract merchant, date, totals, and line items."
                            )
                            ToolCard(
                                title: "Home Asset Manager",
                                subtitle: "Track home assets, warranties, and maintenance with reminders and history."
                            )
                            ToolCard(
                                title: "Budget Education",
                                subtitle: "Guided lessons, tips, and best practices tailored to your budget behavior."
                            )
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screenHorizontal)
                .padding(.top, AppTheme.Spacing.micro)
                .padding(.bottom, AppTheme.Spacing.large)
            }
            .appConstrainContentWidth()
            .coordinateSpace(name: "ToolsView.scroll")
            .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                demoPillVisible = (offsets["ToolsView.scroll"] ?? 0) > -20
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .withAppLogo()
            .environment(\.demoPillVisible, demoPillVisible)
        }
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(title)
                .appSectionTitleText()
            Text(subtitle)
                .appSecondaryBodyText()
                .foregroundStyle(.secondary)
        }
        .appCardSurface()
    }
}

#Preview {
    ToolsView()
}

#Preview("Tools • Dark") {
    ToolsView()
        .preferredColorScheme(.dark)
}

#Preview("Tools • iPad") {
    ToolsView()
        .preferredColorScheme(.dark)
}
