import XCTest
import SwiftData
@testable import EscapeBudget

final class DemoModeReviewVisibilityTests: XCTestCase {
    @MainActor
    func testDemoDataIncomeTransactionsAreClassifiedAsIncome() throws {
        let schema = Schema([
            Account.self,
            CategoryGroup.self,
            Category.self,
            Transaction.self,
            TransactionTag.self,
            TransactionHistoryEntry.self,
            PurchasedItem.self,
            MonthlyAccountTotal.self,
            MonthlyCashflowTotal.self,
            SavingsGoal.self,
            PurchasePlan.self,
            RecurringPurchase.self,
            CustomDashboardWidget.self,
            AppNotification.self,
            AutoRule.self,
            AutoRuleApplication.self,
            TransferPattern.self,
            CategoryPattern.self,
            PayeePattern.self,
            RecurringPattern.self,
            BudgetForecast.self,
            DiagnosticEvent.self,
            ReceiptImage.self,
            DebtAccount.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        DataSeeder.ensureSystemGroups(context: context)
        DemoDataService.generateDemoData(modelContext: context)
        DemoDataService.ensureDemoCategoryRelationships(modelContext: context)

        let standard = TransactionKind.standard.rawValue
        let all = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.kindRawValue == standard }))
        XCTAssertFalse(all.isEmpty, "Expected demo seed to create standard transactions")

        let income = all.filter { $0.amount > 0 && $0.category?.group?.type == .income }
        XCTAssertFalse(income.isEmpty, "Expected demo seed income transactions to be categorized as income")
    }

    @MainActor
    func testDemoDataExpenseCategoriesHaveGroupBacklinks() throws {
        let schema = Schema([
            Account.self,
            CategoryGroup.self,
            Category.self,
            Transaction.self,
            TransactionTag.self,
            TransactionHistoryEntry.self,
            PurchasedItem.self,
            MonthlyAccountTotal.self,
            MonthlyCashflowTotal.self,
            SavingsGoal.self,
            PurchasePlan.self,
            RecurringPurchase.self,
            CustomDashboardWidget.self,
            AppNotification.self,
            AutoRule.self,
            AutoRuleApplication.self,
            TransferPattern.self,
            CategoryPattern.self,
            PayeePattern.self,
            RecurringPattern.self,
            BudgetForecast.self,
            DiagnosticEvent.self,
            ReceiptImage.self,
            DebtAccount.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        DataSeeder.ensureSystemGroups(context: context)
        DemoDataService.generateDemoData(modelContext: context)
        DemoDataService.ensureDemoCategoryRelationships(modelContext: context)

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let expenseGroups = groups.filter { $0.type == .expense && $0.name != "Transfer" }
        XCTAssertFalse(expenseGroups.isEmpty)

        let firstGroup = try XCTUnwrap(expenseGroups.first)
        let firstCategory = try XCTUnwrap(firstGroup.categories?.first)
        XCTAssertEqual(firstCategory.group?.persistentModelID, firstGroup.persistentModelID)
    }
}

