import SwiftUI

struct NotificationsSettingsHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case settings = "Settings"
        case badges = "Badges"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("notificationsHub.selectedTab") private var selectedTabRawValue = Tab.notifications.rawValue
    @State private var demoPillVisible = true
    private let maxContentWidth: CGFloat = 560

    var body: some View {
        NavigationStack {
            hubBody
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        TopChromeTabs(
                            selection: selectedTabBinding,
                            tabs: Tab.allCases.map { .init(id: $0, title: $0.rawValue) }
                        )
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                            .frame(maxWidth: maxContentWidth)
                            .frame(maxWidth: .infinity)
                    }
                    .contentShape(Rectangle())
                    .background(Color.black.opacity(0.001))
                    .zIndex(10)
                }
                .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                    let key: String
                    switch selectedTab {
                    case .notifications:
                        key = "NotificationsView.scroll"
                    case .settings:
                        key = "SettingsView.scroll"
                    case .badges:
                        key = "BadgesView.scroll"
                    }
                    demoPillVisible = (offsets[key] ?? 0) > -20
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
        .environment(\.demoPillVisible, demoPillVisible)
    }

    private var selectedTab: Tab {
        Tab(rawValue: selectedTabRawValue) ?? .notifications
    }

    private var selectedTabBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    @ViewBuilder
    private var hubBody: some View {
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
}
