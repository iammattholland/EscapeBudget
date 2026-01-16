import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var selectedMonth = Date()

    var body: some View {
        NavigationStack {
            ReportsOverviewView(selectedDate: $selectedMonth)
                .navigationTitle("Home")
                .withAppLogo()
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, SavingsGoal.self, Category.self, CategoryGroup.self, TransactionTag.self, MonthlyAccountTotal.self, MonthlyCashflowTotal.self], inMemory: true)
}
