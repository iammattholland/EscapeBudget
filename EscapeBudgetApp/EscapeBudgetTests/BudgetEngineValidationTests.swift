import Testing
import Foundation
@testable import EscapeBudget

@MainActor
struct BudgetEngineValidationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return value
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private func expenseCategory(
        assigned: Decimal,
        budgetType: CategoryBudgetType,
        overspendHandling: CategoryOverspendHandling = .carryNegative,
        createdAt: Date? = nil,
        archivedAfterMonthStart: Date? = nil
    ) -> EscapeBudget.Category {
        let group = CategoryGroup(name: "Expenses", type: .expense)
        let category = EscapeBudget.Category(name: "Test", assigned: assigned)
        category.group = group
        category.budgetType = budgetType
        category.overspendHandling = overspendHandling
        category.createdAt = createdAt
        category.archivedAfterMonthStart = archivedAfterMonthStart
        return category
    }

    private func standardExpense(
        date: Date,
        amount: Decimal,
        category: EscapeBudget.Category
    ) -> Transaction {
        let account = Account(name: "Checking", type: .chequing, balance: 1_000)
        return Transaction(
            date: date,
            payee: "Merchant",
            amount: amount,
            kind: .standard,
            account: account,
            category: category
        )
    }

    @Test func monthlyReset_startsFreshEveryMonth() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let category = expenseCategory(assigned: 100, budgetType: .monthlyReset)
        let januaryExpense = standardExpense(date: january, amount: -120, category: category)
        let calculator = CategoryBudgetCalculator(transactions: [januaryExpense], calendar: calendar)

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(januarySummary.startingAvailable == 0)
        #expect(januarySummary.budgeted == 100)
        #expect(januarySummary.spent == 120)
        #expect(januarySummary.endingAvailable == -20)
        #expect(januarySummary.carryoverToNextMonth == 0)

        #expect(februarySummary.startingAvailable == 0)
        #expect(februarySummary.budgeted == 100)
        #expect(februarySummary.endingAvailable == 100)
        #expect(februarySummary.carryoverToNextMonth == 0)
    }

    @Test func monthlyRollover_carriesNegativeWhenConfigured() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let category = expenseCategory(
            assigned: 100,
            budgetType: .monthlyRollover,
            overspendHandling: .carryNegative
        )
        let januaryExpense = standardExpense(date: january, amount: -150, category: category)
        let februaryExpense = standardExpense(date: february, amount: -20, category: category)
        let calculator = CategoryBudgetCalculator(
            transactions: [januaryExpense, februaryExpense],
            calendar: calendar
        )

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(januarySummary.endingAvailable == -50)
        #expect(januarySummary.carryoverToNextMonth == -50)
        #expect(februarySummary.startingAvailable == -50)
        #expect(februarySummary.budgeted == 100)
        #expect(februarySummary.spent == 20)
        #expect(februarySummary.endingAvailable == 30)
        #expect(februarySummary.carryoverToNextMonth == 30)
    }

    @Test func monthlyRollover_dropsNegativeWhenConfiguredNotToCarry() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let category = expenseCategory(
            assigned: 100,
            budgetType: .monthlyRollover,
            overspendHandling: .doNotCarry
        )
        let januaryExpense = standardExpense(date: january, amount: -150, category: category)
        let februaryExpense = standardExpense(date: february, amount: -20, category: category)
        let calculator = CategoryBudgetCalculator(
            transactions: [januaryExpense, februaryExpense],
            calendar: calendar
        )

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(januarySummary.endingAvailable == -50)
        #expect(januarySummary.carryoverToNextMonth == 0)
        #expect(februarySummary.startingAvailable == 0)
        #expect(februarySummary.endingAvailable == 80)
    }

    @Test func lumpSum_carriesSinglePoolAcrossMonths() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let category = expenseCategory(assigned: 500, budgetType: .lumpSum)
        let januaryExpense = standardExpense(date: january, amount: -100, category: category)
        let februaryExpense = standardExpense(date: february, amount: -50, category: category)
        let calculator = CategoryBudgetCalculator(
            transactions: [januaryExpense, februaryExpense],
            calendar: calendar
        )

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(januarySummary.startingAvailable == 500)
        #expect(januarySummary.budgeted == 0)
        #expect(januarySummary.endingAvailable == 400)
        #expect(januarySummary.carryoverToNextMonth == 400)

        #expect(februarySummary.startingAvailable == 400)
        #expect(februarySummary.spent == 50)
        #expect(februarySummary.endingAvailable == 350)
        #expect(februarySummary.carryoverToNextMonth == 350)
    }

    @Test func monthlyBudgetOverride_changesMonthBudgetedAmount() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let category = expenseCategory(assigned: 100, budgetType: .monthlyReset)
        let februaryOverride = MonthlyCategoryBudget(monthStart: february, amount: 250, category: category)
        let januaryExpense = standardExpense(date: january, amount: -20, category: category)
        let februaryExpense = standardExpense(date: february, amount: -30, category: category)
        let calculator = CategoryBudgetCalculator(
            transactions: [januaryExpense, februaryExpense],
            monthlyBudgets: [februaryOverride],
            calendar: calendar
        )

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(januarySummary.budgeted == 100)
        #expect(februarySummary.budgeted == 250)
        #expect(februarySummary.endingAvailable == 220)
    }

    @Test func archivedCategory_isInactiveAfterArchiveMonth() {
        let january = month(2026, 1)
        let february = month(2026, 2)
        let archivedAtJanuary = month(2026, 1)
        let category = expenseCategory(
            assigned: 100,
            budgetType: .monthlyReset,
            createdAt: month(2025, 12),
            archivedAfterMonthStart: archivedAtJanuary
        )
        let januaryExpense = standardExpense(date: january, amount: -40, category: category)
        let februaryExpense = standardExpense(date: february, amount: -30, category: category)
        let calculator = CategoryBudgetCalculator(
            transactions: [januaryExpense, februaryExpense],
            calendar: calendar
        )

        let januarySummary = calculator.monthSummary(for: category, monthStart: january)
        let februarySummary = calculator.monthSummary(for: category, monthStart: february)

        #expect(category.isActive(inMonthStart: january, calendar: calendar))
        #expect(!category.isActive(inMonthStart: february, calendar: calendar))
        #expect(januarySummary.budgeted == 100)
        #expect(februarySummary.budgeted == 0)
        #expect(februarySummary.spent == 30)
        #expect(februarySummary.endingAvailable == -30)
    }
}
