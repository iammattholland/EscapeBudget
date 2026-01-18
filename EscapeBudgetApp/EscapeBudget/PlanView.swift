import SwiftUI
import SwiftData

struct PlanView: View {
    enum PlanSection: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case purchases = "Purchases"
        case forecast = "Forecast"
        case retirement = "Retirement"
        
        var id: String { rawValue }
    }
    
    @State private var selectedSection: PlanSection = .goals
    @State private var demoPillVisible = true
    
    var body: some View {
        NavigationStack {
            planBody
                .safeAreaInset(edge: .top, spacing: 0) {
                    TopChromeTabs(
                        selection: $selectedSection,
                        tabs: PlanSection.allCases.map { .init(id: $0, title: $0.rawValue) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                }
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
            .navigationTitle("Plan")
            .withAppLogo()
            .environment(\.demoPillVisible, demoPillVisible)
        }
    }

    @ViewBuilder
    private var planBody: some View {
        switch selectedSection {
        case .goals:
            SavingsGoalsView()
        case .purchases:
            PurchasePlannerView()
        case .forecast:
            PlanForecastHubView()
        case .retirement:
            RetirementView()
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

    private var isEmptyForecastHub: Bool {
        let hasActiveRecurring = recurringPurchases.contains { $0.isActive }
        let hasPlannedWithDate = purchasePlans.contains { !$0.isPurchased && $0.purchaseDate != nil }
        return !(hasActiveRecurring || hasPlannedWithDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmptyForecastHub {
                SpendingForecastView()
                    .onAppear { selectedTab = .spending }
            } else {
                Picker("Forecast", selection: $selectedTab) {
                    ForEach(ForecastTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .topChromeSegmentedStyle(isCompact: true)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

                Group {
                    switch selectedTab {
                    case .spending:
                        SpendingForecastView()
                    case .cashFlow:
                        CashFlowForecastView()
                    }
                }
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
