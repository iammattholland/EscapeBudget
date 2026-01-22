import SwiftUI

struct ToolsView: View {
    @State private var demoPillVisible = true

    var body: some View {
        NavigationStack {
            List {
                ScrollOffsetReader(coordinateSpace: "ToolsView.scroll", id: "ToolsView.scroll")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                Section {
                    HStack(spacing: AppTheme.Spacing.tight) {
                        Image(systemName: "hammer")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                        AppSectionHeader(
                            title: "Tools",
                            subtitle: "Your toolbox for deeper insights and planning."
                        )
                    }
                    .padding(.vertical, AppTheme.Spacing.micro)
                }

                Section("Available Now") {
                    NavigationLink {
                        YearEndReviewView()
                    } label: {
                        ToolComingItem(
                            title: "Year End Review",
                            subtitle: "A Spotify‑wrapped style recap with highlights, trends, and insights."
                        )
                    }
                    NavigationLink {
                        DebtPayoffPlannerView()
                    } label: {
                        ToolComingItem(
                            title: "Debt Payoff Planner",
                            subtitle: "Build payoff plans, compare strategies, and track progress toward zero."
                        )
                    }
                    NavigationLink {
                        BillsDashboardView()
                    } label: {
                        ToolComingItem(
                            title: "Bills Dashboard",
                            subtitle: "An overview of your repeating monthly bills with due dates, totals, and trends."
                        )
                    }
                }

                Section("Planned Features") {
                    ToolComingItem(
                        title: "Receipt Scanner",
                        subtitle: "Capture receipts and auto-extract merchant, date, totals, and line items."
                    )
                    ToolComingItem(
                        title: "Home Asset Manager",
                        subtitle: "Track home assets, warranties, and maintenance with reminders and history."
                    )
                    ToolComingItem(
                        title: "Budget Education",
                        subtitle: "Guided lessons, tips, and best practices tailored to your budget behavior."
                    )
                }
            }
            .appConstrainContentWidth()
            .coordinateSpace(name: "ToolsView.scroll")
            .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                demoPillVisible = (offsets["ToolsView.scroll"] ?? 0) > -20
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .withAppLogo()
            .environment(\.demoPillVisible, demoPillVisible)
        }
    }
}

private struct ToolComingItem: View {
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
        .padding(.vertical, AppTheme.Spacing.micro)
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
