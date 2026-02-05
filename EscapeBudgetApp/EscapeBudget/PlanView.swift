import SwiftUI
import SwiftData

struct PlanView: View {
    enum PlanSection: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case purchases = "Spend"
        case forecast = "Forecast"
        case retirement = "Retire"
        
        var id: String { rawValue }
    }
    
    @State private var selectedSection: PlanSection = .goals
    @State private var demoPillVisible = true
    
    var body: some View {
        NavigationStack {
            planBody
                .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                    let key: String
                    switch selectedSection {
                    case .goals:
                        key = "SavingsGoalsView.scroll"
                    case .purchases:
                        key = "PurchasePlannerView.scroll"
                    case .forecast:
                        key = "PlanForecastHubView.scroll"
                    case .retirement:
                        key = "RetirementView.scroll"
                    }
                    demoPillVisible = (offsets[key] ?? 0) > -20
                }
            .navigationTitle(navigationTitle)
            .withAppLogo()
            .environment(\.demoPillVisible, demoPillVisible)
            .appLightModePageBackground()
        }
    }

    private var planTopChrome: some View {
        VStack(spacing: 0) {
            TopChromeTabs(
                selection: $selectedSection,
                tabs: PlanSection.allCases.map { .init(id: $0, title: $0.rawValue) }
            )
            .topMenuBarStyle()
        }
    }

    @ViewBuilder
    private var planBody: some View {
        switch selectedSection {
        case .goals:
            SavingsGoalsView(topChrome: { AnyView(planTopChrome) })
        case .purchases:
            PurchasePlannerView(topChrome: { AnyView(planTopChrome) })
        case .forecast:
            PlanForecastHubView(topChrome: { AnyView(planTopChrome) })
        case .retirement:
            RetirementView(topChrome: { AnyView(planTopChrome) })
        }
    }

    private var navigationTitle: String {
        switch selectedSection {
        case .goals:
            return "Plan Goals"
        case .purchases:
            return "Plan Spending"
        case .forecast:
            return "Plan Forecast"
        case .retirement:
            return "Plan Retirement"
        }
    }
}

private struct PlanForecastHubView: View {
    private enum ForecastTab: String, CaseIterable, Identifiable {
        case spending = "Spending"
        case cashFlow = "Cash Flow"

        var id: String { rawValue }
    }

    @Query(sort: \RecurringPurchase.nextDate) private var recurringPurchases: [RecurringPurchase]
    @Query(sort: \PurchasePlan.purchaseDate) private var purchasePlans: [PurchasePlan]

    @State private var selectedTab: ForecastTab = .spending
    private let topChrome: AnyView?

    init(topChrome: (() -> AnyView)? = nil) {
        self.topChrome = topChrome?()
    }

    private var isEmptyForecastHub: Bool {
        let hasActiveRecurring = recurringPurchases.contains { $0.isActive }
        let hasPlannedWithDate = purchasePlans.contains { !$0.isPurchased && $0.purchaseDate != nil }
        return !(hasActiveRecurring || hasPlannedWithDate)
    }

    var body: some View {
        let forecastTabs = TopChromeTabs(
            selection: $selectedTab,
            tabs: ForecastTab.allCases.map { .init(id: $0, title: $0.rawValue) },
            isCompact: true
        )
        .topMenuBarStyle(isCompact: true)

        let combinedTopChrome: AnyView? = {
            let tabsView = AnyView(forecastTabs)
            if let topChrome {
                return AnyView(VStack(spacing: AppDesign.Theme.Layout.topChromeContentGap) {
                    topChrome
                    tabsView
                })
            }
            return tabsView
        }()

        if isEmptyForecastHub {
            SpendingForecastView(topChrome: combinedTopChrome)
                .onAppear { selectedTab = .spending }
        } else {
            switch selectedTab {
            case .spending:
                SpendingForecastView(topChrome: combinedTopChrome)
            case .cashFlow:
                CashFlowForecastView(topChrome: combinedTopChrome)
            }
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(
            for: [
                CategoryGroup.self,
                Category.self,
                Account.self,
                Transaction.self,
                TransactionHistoryEntry.self,
                TransactionTag.self,
                MonthlyCashflowTotal.self,
                RecurringPurchase.self,
                PurchasePlan.self,
                SavingsGoal.self
            ],
            inMemory: true
        )
}

#Preview("Plan • Dark") {
    PlanView()
        .modelContainer(
            for: [
                CategoryGroup.self,
                Category.self,
                Account.self,
                Transaction.self,
                TransactionHistoryEntry.self,
                TransactionTag.self,
                MonthlyCashflowTotal.self,
                RecurringPurchase.self,
                PurchasePlan.self,
                SavingsGoal.self
            ],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}

#Preview("Plan • iPad") {
    PlanView()
        .modelContainer(
            for: [
                CategoryGroup.self,
                Category.self,
                Account.self,
                Transaction.self,
                TransactionHistoryEntry.self,
                TransactionTag.self,
                MonthlyCashflowTotal.self,
                RecurringPurchase.self,
                PurchasePlan.self,
                SavingsGoal.self
            ],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
