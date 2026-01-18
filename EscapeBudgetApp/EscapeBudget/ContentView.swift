import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var navigator: AppNavigator
    @AppStorage("isDemoMode") private var isDemoMode = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad / Mac - Use sidebar navigation
                iPadMacLayout
            } else {
                // iPhone - Use tabs
                iPhoneLayout
            }
        }
        .onChange(of: navigator.selectedTab) { _, _ in
#if canImport(UIKit)
            KeyboardUtilities.dismiss()
#endif
        }
    }
    
    // MARK: - iPhone Layout (TabView)
    
    private var iPhoneLayout: some View {
        TabView(selection: $navigator.selectedTab) {
            ManageView()
                .tabItem {
                    Label("Manage", systemImage: AppTab.manage.icon)
                }
                .tag(AppTab.manage)

            PlanView()
                .undoRedoToolbar()
                .tabItem {
                    Label("Plan", systemImage: AppTab.plan.icon)
                }
                .tag(AppTab.plan)

            HomeView()
                .undoRedoToolbar()
                .tabItem {
                    Label("Home", systemImage: AppTab.home.icon)
                }
                .tag(AppTab.home)

            ReviewView()
                .undoRedoToolbar()
                .tabItem {
                    Label("Review", systemImage: AppTab.review.icon)
                }
                .tag(AppTab.review)

            ToolsView()
                .tabItem {
                    Label("Tools", systemImage: AppTab.tools.icon)
                }
                .tag(AppTab.tools)
        }
    }
    
    // MARK: - iPad/Mac Layout (Sidebar)
    @State private var selectedSidebarTab: AppTab? = .home
    
    private var iPadMacLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $selectedSidebarTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Escape\u{00A0}Budget")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            #endif
            .onAppear {
                selectedSidebarTab = navigator.selectedTab
            }
            .onChange(of: navigator.selectedTab) { _, newValue in
                if selectedSidebarTab != newValue {
                    selectedSidebarTab = newValue
                }
            }
            .onChange(of: selectedSidebarTab) { _, newValue in
                if let newValue, navigator.selectedTab != newValue {
                    navigator.selectedTab = newValue
                }
            }
        } detail: {
            Group {
                switch selectedSidebarTab ?? navigator.selectedTab {
                case .manage:
                    ManageView()
                case .plan:
                    PlanView()
                case .home:
                    HomeView()
                case .review:
                    ReviewView()
                case .tools:
                    ToolsView()
                }
            }
            .undoRedoToolbar()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.shared)
}
