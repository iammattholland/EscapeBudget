import SwiftUI

struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "hammer")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tools")
                                .font(.headline)
                            Text("Your toolbox for deeper insights and planning.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .withAppLogo()
        }
    }
}

private struct ToolComingItem: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ToolsView()
}
