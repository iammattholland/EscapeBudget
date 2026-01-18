import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var selectedMonth = Date()
    @State private var demoPillVisible = true

    var body: some View {
        NavigationStack {
            ReportsOverviewView(selectedDate: $selectedMonth)
                .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                    demoPillVisible = (offsets["ReportsOverviewView.scroll"] ?? 0) > -20
                }
                .navigationTitle("Home")
                .withAppLogo()
                .environment(\.demoPillVisible, demoPillVisible)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, SavingsGoal.self, Category.self, CategoryGroup.self, TransactionTag.self, MonthlyAccountTotal.self, MonthlyCashflowTotal.self], inMemory: true)
}
