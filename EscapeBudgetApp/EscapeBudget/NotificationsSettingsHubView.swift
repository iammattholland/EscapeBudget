import SwiftUI

struct NotificationsSettingsHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case settings = "Settings"
        case badges = "Badges"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .notifications
    private let maxContentWidth: CGFloat = 560

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)

                Group {
                    switch selectedTab {
                    case .notifications:
                        NotificationsView(embedded: true)
                    case .settings:
                        SettingsView(embedded: true, showsAppLogo: false)
                    case .badges:
                        BadgesView()
                    }
                }
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(selectedTab.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .solidPresentationBackground()
    }
}
