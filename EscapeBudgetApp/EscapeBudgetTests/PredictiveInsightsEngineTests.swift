import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

@MainActor
struct PredictiveInsightsEngineTests {
    private func createTestContainer() -> ModelContainer {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            CategoryGroup.self,
            TransactionTag.self,
            TransactionHistoryEntry.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }

    @Test func testIncomeVariationDoesNotMiscompareFullFebruaryMonth() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let incomeGroup = CategoryGroup(name: "Income", order: 0, type: .income)
        let paycheck = Category(name: "Paycheck", assigned: 0)
        paycheck.group = incomeGroup
        incomeGroup.categories = [paycheck]
        context.insert(incomeGroup)
        context.insert(paycheck)

        let calendar = Calendar(identifier: .gregorian)
        let jan1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let jan15 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let feb1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let feb15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let febEnd = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!.addingTimeInterval(-1)

        let janIncome = [
            Transaction(date: jan1, payee: "Employer", amount: 2500, account: checking, category: paycheck),
            Transaction(date: jan15, payee: "Employer", amount: 2500, account: checking, category: paycheck)
        ]
        let febIncome = [
            Transaction(date: feb1, payee: "Employer", amount: 2500, account: checking, category: paycheck),
            Transaction(date: feb15, payee: "Employer", amount: 2500, account: checking, category: paycheck)
        ]
        for tx in janIncome + febIncome {
            context.insert(tx)
        }
        try context.save()

        // Pass only current-period transactions in.
        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: febIncome,
            dateRange: (start: feb1, end: febEnd),
            categories: [],
            currentIncome: 5000,
            currentExpenses: 0,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.incomeVariation })
    }
}
