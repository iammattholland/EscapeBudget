import Foundation
import SwiftData

enum UITestSeedData {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        let explicitSeedArgs = arguments.filter { $0.hasPrefix("ui_seed_") }
        let useDefaultSeeds = explicitSeedArgs.isEmpty

        let seedRecurring = useDefaultSeeds || arguments.contains("ui_seed_recurring")
        let seedTrend = useDefaultSeeds || arguments.contains("ui_seed_trend")
        let seedIncomeVariation = useDefaultSeeds || arguments.contains("ui_seed_income_variation")
        let seedSavingsOpportunity = arguments.contains("ui_seed_savings_opportunity")
        let seedUpcomingBill = arguments.contains("ui_seed_upcoming_bill")
        let seedBudgetProjection = arguments.contains("ui_seed_budget_projection")
        let seedUnusualSpending = arguments.contains("ui_seed_unusual_spending")

        let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let existingTransactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []

        let account: Account = {
            if let existing = existingAccounts.first(where: { $0.isDemoData && $0.name == "UI Test Account" }) {
                return existing
            }
            let created = Account(name: "UI Test Account", type: .chequing, balance: 1000, isDemoData: true)
            context.insert(created)
            return created
        }()

        if !existingTransactions.contains(where: { $0.isDemoData && $0.payee == "Seed Transaction" }) {
            let tx = Transaction(
                date: Date(),
                payee: "Seed Transaction",
                amount: Decimal(-12.34),
                memo: nil,
                status: .uncleared,
                kind: .standard,
                transferID: nil,
                account: account,
                category: nil,
                tags: nil,
                isDemoData: true
            )
            context.insert(tx)
        }

        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let monthEnd = calendar.date(byAdding: .day, value: max(0, daysInMonth - 1), to: monthStart) ?? now

        // Ensure an income category exists for income-variation + savings-opportunity tests.
        let incomeGroupType = CategoryGroupType.income.rawValue
        let incomeGroupDescriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == incomeGroupType })
        let incomeGroup = (try? context.fetch(incomeGroupDescriptor))?.first

        let salaryCategory: Category? = {
            guard let incomeGroup else { return nil }
            if let existing = (incomeGroup.categories ?? []).first(where: { $0.name == "Salary" }) {
                return existing
            }
            let created = Category(name: "Salary", assigned: 0, activity: 0, order: 0, isDemoData: true)
            created.group = incomeGroup
            context.insert(created)
            return created
        }()

        if seedRecurring {
            let recurringPayee = "Netflix"
            let existingRecurringCount = existingTransactions.filter { $0.isDemoData && $0.payee == recurringPayee && $0.amount < 0 }.count

            if existingRecurringCount < 2 {
                let first = Transaction(
                    date: monthStart,
                    payee: recurringPayee,
                    amount: Decimal(-15.99),
                    memo: "Subscription",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )
                let second = Transaction(
                    date: monthEnd,
                    payee: recurringPayee,
                    amount: Decimal(-15.99),
                    memo: "Subscription",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )

                if existingRecurringCount == 0 {
                    context.insert(first)
                    context.insert(second)
                } else {
                    context.insert(second)
                }
            }
        }

        if seedIncomeVariation, let salaryCategory {
            let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            let currentIncomePayee = "UI Test Payroll"

            let hasCurrentIncome = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                tx.isDemoData &&
                tx.payee == currentIncomePayee &&
                tx.amount > 0 &&
                tx.date >= monthStart &&
                tx.date <= monthEnd
            })))?.isEmpty == false

            let hasPreviousIncome = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                tx.isDemoData &&
                tx.payee == currentIncomePayee &&
                tx.amount > 0 &&
                tx.date >= previousMonthStart &&
                tx.date < monthStart
            })))?.isEmpty == false

            if !hasPreviousIncome {
                let previous = Transaction(
                    date: calendar.date(byAdding: .day, value: 2, to: previousMonthStart) ?? previousMonthStart,
                    payee: currentIncomePayee,
                    amount: Decimal(5000),
                    memo: "UI test income (previous)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: salaryCategory,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(previous)
            }

            if !hasCurrentIncome {
                let current = Transaction(
                    date: calendar.date(byAdding: .day, value: 2, to: monthStart) ?? monthStart,
                    payee: currentIncomePayee,
                    amount: Decimal(4000),
                    memo: "UI test income (current)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: salaryCategory,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(current)
            }
        }

        if seedSavingsOpportunity, let salaryCategory {
            let incomePayee = "UI Test Payroll"
            let expensePayee = "UI Test Expense"

            let hasIncome = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                tx.isDemoData &&
                tx.payee == incomePayee &&
                tx.amount > 0 &&
                tx.date >= monthStart &&
                tx.date <= monthEnd
            })))?.isEmpty == false

            if !hasIncome {
                let income = Transaction(
                    date: calendar.date(byAdding: .day, value: 1, to: monthStart) ?? monthStart,
                    payee: incomePayee,
                    amount: Decimal(100),
                    memo: "UI test income (low)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: salaryCategory,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(income)
            }

            let hasExpense = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                tx.isDemoData &&
                tx.payee == expensePayee &&
                tx.amount < 0 &&
                tx.date >= monthStart &&
                tx.date <= monthEnd
            })))?.isEmpty == false

            if !hasExpense {
                let expense = Transaction(
                    date: calendar.date(byAdding: .day, value: 2, to: monthStart) ?? monthStart,
                    payee: expensePayee,
                    amount: Decimal(-200),
                    memo: "UI test expense (high)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(expense)
            }
        }

        if seedUpcomingBill {
            let payee = "Upcoming Seed"
            let dates: [Date] = [-87, -57, -27].compactMap { calendar.date(byAdding: .day, value: $0, to: now) }

            let existing = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                tx.isDemoData &&
                tx.payee == payee &&
                tx.amount < 0 &&
                tx.kindRawValue == "Standard"
            }))) ?? []

            for date in dates {
                if existing.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) { continue }

                let tx = Transaction(
                    date: date,
                    payee: payee,
                    amount: Decimal(-42),
                    memo: "UI test upcoming bill seed",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(tx)
            }
        }

        if seedTrend {
            let trendPayee = "Trend Seed"
            let hasTrendCurrent = existingTransactions.contains { tx in
                tx.isDemoData &&
                tx.payee == trendPayee &&
                tx.amount < 0 &&
                tx.date >= monthStart &&
                tx.date <= monthEnd
            }

            if !hasTrendCurrent {
                let current = Transaction(
                    date: calendar.date(byAdding: .day, value: 10, to: monthStart) ?? now,
                    payee: trendPayee,
                    amount: Decimal(-200),
                    memo: "Trend seed (current)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(current)
            }

            let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            let hasTrendPrevious = existingTransactions.contains { tx in
                tx.isDemoData &&
                tx.payee == trendPayee &&
                tx.amount < 0 &&
                tx.date >= previousMonthStart &&
                tx.date < monthStart
            }

            if !hasTrendPrevious {
                let previous = Transaction(
                    date: calendar.date(byAdding: .day, value: 10, to: previousMonthStart) ?? previousMonthStart,
                    payee: trendPayee,
                    amount: Decimal(-100),
                    memo: "Trend seed (previous)",
                    status: .uncleared,
                    kind: .standard,
                    transferID: nil,
                    account: account,
                    category: nil,
                    tags: nil,
                    isDemoData: true
                )
                context.insert(previous)
            }
        }

        if seedBudgetProjection || seedUnusualSpending {
            let expensesGroup: CategoryGroup = {
                if let existing = (try? context.fetch(FetchDescriptor<CategoryGroup>()))?
                    .first(where: { $0.isDemoData && $0.type == .expense && $0.name == "UI Test Expenses" }) {
                    return existing
                }
                let created = CategoryGroup(name: "UI Test Expenses", order: 0, type: .expense, isDemoData: true)
                context.insert(created)
                return created
            }()

            let groceriesCategory: Category = {
                if let existing = (expensesGroup.categories ?? []).first(where: { $0.isDemoData && $0.name == "Groceries" }) {
                    return existing
                }
                let created = Category(name: "Groceries", assigned: 0, activity: 0, order: 0, isDemoData: true)
                created.group = expensesGroup
                context.insert(created)
                return created
            }()

            if seedBudgetProjection {
                groceriesCategory.assigned = 50
                let payee = "UI Test Groceries"
                let hasCurrent = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                    tx.isDemoData &&
                    tx.payee == payee &&
                    tx.amount < 0 &&
                    tx.date >= monthStart &&
                    tx.date <= monthEnd
                })))?.isEmpty == false

                if !hasCurrent {
                    let current = Transaction(
                        date: calendar.date(byAdding: .day, value: 5, to: monthStart) ?? now,
                        payee: payee,
                        amount: Decimal(-200),
                        memo: "UI test groceries (current)",
                        status: .uncleared,
                        kind: .standard,
                        transferID: nil,
                        account: account,
                        category: groceriesCategory,
                        tags: nil,
                        isDemoData: true
                    )
                    context.insert(current)
                }
            }

            if seedUnusualSpending {
                groceriesCategory.assigned = 0
                let payee = "UI Test Groceries"

                let hasCurrent = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                    tx.isDemoData &&
                    tx.payee == payee &&
                    tx.amount < 0 &&
                    tx.date >= monthStart &&
                    tx.date <= monthEnd
                })))?.isEmpty == false

                if !hasCurrent {
                    let current = Transaction(
                        date: calendar.date(byAdding: .day, value: 5, to: monthStart) ?? now,
                        payee: payee,
                        amount: Decimal(-200),
                        memo: "UI test groceries (current)",
                        status: .uncleared,
                        kind: .standard,
                        transferID: nil,
                        account: account,
                        category: groceriesCategory,
                        tags: nil,
                        isDemoData: true
                    )
                    context.insert(current)
                }

                for monthsBack in 1...3 {
                    let historicalMonthStart = calendar.date(byAdding: .month, value: -monthsBack, to: monthStart) ?? monthStart
                    let historicalMonthEnd = calendar.date(byAdding: .month, value: 1, to: historicalMonthStart) ?? monthStart
                    let hasHistorical = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { tx in
                        tx.isDemoData &&
                        tx.payee == payee &&
                        tx.amount < 0 &&
                        tx.date >= historicalMonthStart &&
                        tx.date < historicalMonthEnd
                    })))?.isEmpty == false
                    if hasHistorical { continue }

                    let historicalDate = calendar.date(byAdding: .day, value: 5, to: historicalMonthStart) ?? historicalMonthStart
                    let historical = Transaction(
                        date: historicalDate,
                        payee: payee,
                        amount: Decimal(-50),
                        memo: "UI test groceries (historical)",
                        status: .uncleared,
                        kind: .standard,
                        transferID: nil,
                        account: account,
                        category: groceriesCategory,
                        tags: nil,
                        isDemoData: true
                    )
                    context.insert(historical)
                }
            }
        }

        _ = context.safeSave(context: "UITestSeedData.seedIfNeeded", showErrorToUser: false)
    }
}
