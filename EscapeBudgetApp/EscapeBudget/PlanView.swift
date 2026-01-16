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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Section", selection: $selectedSection) {
                    ForEach(PlanSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                Group {
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
            .navigationTitle("Plan")
            .withAppLogo()
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
                .padding(.horizontal)
                .padding(.bottom, 8)

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
