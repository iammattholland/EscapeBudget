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

    @Test func testIncomeVariationDoesNotShowWhenIncomeIsUnchanged() throws {
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
        for tx in janIncome + febIncome { context.insert(tx) }
        try context.save()

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

    @Test func testSpendingTrendAccountsForRefundsInExpenseCategories() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let expensesGroup = CategoryGroup(name: "Expenses", order: 0, type: .expense)
        let groceries = Category(name: "Groceries", assigned: 0)
        groceries.group = expensesGroup
        expensesGroup.categories = [groceries]
        context.insert(expensesGroup)
        context.insert(groceries)

        let calendar = Calendar(identifier: .gregorian)
        let feb1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let feb15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let mar1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let mar10 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let marEnd = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!.addingTimeInterval(-1)

        // Previous month: $1000 spend, $500 refund -> net outflow $500.
        let previous = [
            Transaction(date: feb1, payee: "Grocer", amount: -1000, account: checking, category: groceries),
            Transaction(date: feb15, payee: "Grocer Refund", amount: 500, account: checking, category: groceries)
        ]
        // Current month: $500 spend -> net outflow $500.
        let current = [
            Transaction(date: mar10, payee: "Grocer", amount: -500, account: checking, category: groceries)
        ]
        for tx in previous + current { context.insert(tx) }
        try context.save()

        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: current,
            dateRange: (start: mar1, end: marEnd),
            categories: [groceries],
            currentIncome: 0,
            currentExpenses: 500,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.spendingTrend })
    }

    @Test func testUpcomingBillDoesNotTriggerOnIrregularIntervals() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let d1 = calendar.date(byAdding: .day, value: -70, to: now)!
        let d2 = calendar.date(byAdding: .day, value: -60, to: now)! // 10 days later
        let d3 = calendar.date(byAdding: .day, value: -10, to: now)! // 50 days later (avg 30 but irregular)

        let txs = [
            Transaction(date: d1, payee: "Weird Subscription", amount: -10, account: checking, category: nil),
            Transaction(date: d2, payee: "Weird Subscription", amount: -10, account: checking, category: nil),
            Transaction(date: d3, payee: "Weird Subscription", amount: -10, account: checking, category: nil)
        ]
        for tx in txs { context.insert(tx) }
        try context.save()

        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: [],
            dateRange: (start: d3, end: now),
            categories: [],
            currentIncome: 0,
            currentExpenses: 0,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.upcomingBill })
    }

    @Test func testRecurringExpenseDoesNotTriggerWhenAmountsAreUnstable() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let calendar = Calendar(identifier: .gregorian)
        let m1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let m2 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        let m3 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!

        let txs = [
            Transaction(date: m1, payee: "Unstable", amount: -10, account: checking, category: nil),
            Transaction(date: m2, payee: "Unstable", amount: -100, account: checking, category: nil),
            Transaction(date: m3, payee: "Unstable", amount: -10, account: checking, category: nil)
        ]
        for tx in txs { context.insert(tx) }
        try context.save()

        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: txs,
            dateRange: (start: m1, end: m3),
            categories: [],
            currentIncome: 0,
            currentExpenses: 0,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.recurringExpenseDetected })
    }

    @Test func testUnusualSpendingDoesNotTriggerWithInsufficientHistory() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let expensesGroup = CategoryGroup(name: "Expenses", order: 0, type: .expense)
        let groceries = Category(name: "Groceries", assigned: 0)
        groceries.group = expensesGroup
        expensesGroup.categories = [groceries]
        context.insert(expensesGroup)
        context.insert(groceries)

        let calendar = Calendar(identifier: .gregorian)
        let jan10 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let feb10 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        let mar1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let marEnd = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!.addingTimeInterval(-1)

        // Only 2 historical tx (insufficient for unusual-spending claim).
        let historical = [
            Transaction(date: jan10, payee: "Grocer", amount: -100, account: checking, category: groceries),
            Transaction(date: feb10, payee: "Grocer", amount: -100, account: checking, category: groceries)
        ]
        let current = [
            Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!, payee: "Grocer", amount: -500, account: checking, category: groceries)
        ]
        for tx in historical + current { context.insert(tx) }
        try context.save()

        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: current,
            dateRange: (start: mar1, end: marEnd),
            categories: [groceries],
            currentIncome: 0,
            currentExpenses: 500,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.unusualSpending })
    }

    @Test func testUnusualSpendingDoesNotTriggerOnTinyBaseline() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let checking = Account(name: "Checking", type: .chequing, balance: 0)
        context.insert(checking)

        let expensesGroup = CategoryGroup(name: "Expenses", order: 0, type: .expense)
        let coffee = Category(name: "Coffee", assigned: 0)
        coffee.group = expensesGroup
        expensesGroup.categories = [coffee]
        context.insert(expensesGroup)
        context.insert(coffee)

        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let monthEnd = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!.addingTimeInterval(-1)

        // 3 months of tiny history ($10 avg), current $25. Should not trigger.
        let historyDates = [
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!,
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        ]
        for d in historyDates {
            context.insert(Transaction(date: d, payee: "Cafe", amount: -10, account: checking, category: coffee))
        }
        let current = [Transaction(date: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!, payee: "Cafe", amount: -25, account: checking, category: coffee)]
        for tx in current { context.insert(tx) }
        try context.save()

        let engine = PredictiveInsightsEngine(modelContext: context)
        let insights = engine.generateInsights(
            transactions: current,
            dateRange: (start: monthStart, end: monthEnd),
            categories: [coffee],
            currentIncome: 0,
            currentExpenses: 25,
            savingsRate: nil,
            currencyCode: "USD"
        )

        #expect(insights.allSatisfy { $0.type != PredictiveInsightsEngine.Insight.InsightType.unusualSpending })
    }
}
