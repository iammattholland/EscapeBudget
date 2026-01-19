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
                    HStack(spacing: 12) {
                        Image(systemName: "hammer")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                        AppSectionHeader(
                            title: "Tools",
                            subtitle: "Your toolbox for deeper insights and planning."
                        )
                    }
                    .padding(.vertical, 4)
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
                }

                Section("Planned Features") {
                    ToolComingItem(
                        title: "Debt Payoff Planner",
                        subtitle: "Build payoff plans, compare strategies, and track progress toward zero."
                    )
                    ToolComingItem(
                        title: "Bills Dashboard",
                        subtitle: "An overview of your repeating monthly bills with due dates, totals, and trends."
                    )
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appSectionTitleText()
            Text(subtitle)
                .appSecondaryBodyText()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        .previewDevice("iPad Pro (12.9-inch) (6th generation)")
}
