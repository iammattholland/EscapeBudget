import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

@MainActor
struct AutoRulesServiceTests {

    // MARK: - Test Setup

    private func createTestContainer() -> ModelContainer {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            TransactionTag.self,
            AutoRule.self,
            AutoRuleApplication.self,
            CategoryGroup.self,
            TransactionHistoryEntry.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }

    private func createTestData(context: ModelContext) -> (account: Account, category: EscapeBudget.Category, tags: [TransactionTag]) {
        let account = Account(name: "Test Account", type: .chequing, balance: 1000)
        context.insert(account)

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)

        let category = EscapeBudget.Category(name: "Test Category")
        category.group = group
        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        context.insert(category)

        let tag1 = TransactionTag(name: "Tag1", colorHex: "#007AFF")
        let tag2 = TransactionTag(name: "Tag2", colorHex: "#34C759")
        context.insert(tag1)
        context.insert(tag2)

        try! context.save()

        return (account, category, [tag1, tag2])
    }

    // MARK: - Payee Matching Tests

    @Test func testPayeeMatchingContains() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Starbucks"
        rule.matchPayeeCaseSensitive = false
        context.insert(rule)

        #expect(rule.matches(payee: "Starbucks Coffee", account: account, amount: Decimal(-5.00)))
        #expect(rule.matches(payee: "STARBUCKS", account: account, amount: Decimal(-5.00)))
        #expect(rule.matches(payee: "starbucks downtown", account: account, amount: Decimal(-5.00)))
        #expect(!rule.matches(payee: "Coffee Shop", account: account, amount: Decimal(-5.00)))
    }

    @Test func testPayeeMatchingEquals() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .equals
        rule.matchPayeeValue = "Amazon"
        rule.matchPayeeCaseSensitive = false
        context.insert(rule)

        #expect(rule.matches(payee: "Amazon", account: account, amount: Decimal(-50.00)))
        #expect(rule.matches(payee: "AMAZON", account: account, amount: Decimal(-50.00)))
        #expect(!rule.matches(payee: "Amazon Prime", account: account, amount: Decimal(-50.00)))
        #expect(!rule.matches(payee: "The Amazon Store", account: account, amount: Decimal(-50.00)))
    }

    @Test func testPayeeMatchingStartsWith() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .startsWith
        rule.matchPayeeValue = "WALMART"
        rule.matchPayeeCaseSensitive = false
        context.insert(rule)

        #expect(rule.matches(payee: "Walmart Supercenter", account: account, amount: Decimal(-100.00)))
        #expect(rule.matches(payee: "WALMART #1234", account: account, amount: Decimal(-100.00)))
        #expect(!rule.matches(payee: "Target Walmart", account: account, amount: Decimal(-100.00)))
    }

    @Test func testPayeeMatchingEndsWith() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .endsWith
        rule.matchPayeeValue = "Inc"
        rule.matchPayeeCaseSensitive = false
        context.insert(rule)

        #expect(rule.matches(payee: "Apple Inc", account: account, amount: Decimal(-999.00)))
        #expect(rule.matches(payee: "Microsoft INC", account: account, amount: Decimal(-500.00)))
        #expect(!rule.matches(payee: "Inc Incorporated", account: account, amount: Decimal(-100.00)))
    }

    @Test func testPayeeMatchingCaseSensitive() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .equals
        rule.matchPayeeValue = "GitHub"
        rule.matchPayeeCaseSensitive = true
        context.insert(rule)

        #expect(rule.matches(payee: "GitHub", account: account, amount: Decimal(-10.00)))
        #expect(!rule.matches(payee: "github", account: account, amount: Decimal(-10.00)))
        #expect(!rule.matches(payee: "GITHUB", account: account, amount: Decimal(-10.00)))
    }

    // MARK: - Amount Matching Tests

    @Test func testAmountMatchingEquals() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchAmountCondition = .equals
        rule.matchAmountValue = Decimal(9.99)
        context.insert(rule)

        #expect(rule.matches(payee: "Netflix", account: account, amount: Decimal(9.99)))
        #expect(!rule.matches(payee: "Netflix", account: account, amount: Decimal(10.00)))
        #expect(!rule.matches(payee: "Netflix", account: account, amount: Decimal(9.98)))
    }

    @Test func testAmountMatchingGreaterThan() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchAmountCondition = .greaterThan
        rule.matchAmountValue = Decimal(100.00)
        context.insert(rule)

        #expect(rule.matches(payee: "Large Purchase", account: account, amount: Decimal(100.01)))
        #expect(rule.matches(payee: "Large Purchase", account: account, amount: Decimal(500.00)))
        #expect(!rule.matches(payee: "Small Purchase", account: account, amount: Decimal(100.00)))
        #expect(!rule.matches(payee: "Small Purchase", account: account, amount: Decimal(99.99)))
    }

    @Test func testAmountMatchingLessThan() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchAmountCondition = .lessThan
        rule.matchAmountValue = Decimal(-50.00)
        context.insert(rule)

        #expect(rule.matches(payee: "Small Expense", account: account, amount: Decimal(-51.00)))
        #expect(rule.matches(payee: "Small Expense", account: account, amount: Decimal(-100.00)))
        #expect(!rule.matches(payee: "Large Expense", account: account, amount: Decimal(-50.00)))
        #expect(!rule.matches(payee: "Large Expense", account: account, amount: Decimal(-49.99)))
    }

    @Test func testAmountMatchingBetween() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchAmountCondition = .between
        rule.matchAmountValue = Decimal(10.00)
        rule.matchAmountValueMax = Decimal(50.00)
        context.insert(rule)

        #expect(rule.matches(payee: "Mid Range", account: account, amount: Decimal(10.00)))
        #expect(rule.matches(payee: "Mid Range", account: account, amount: Decimal(25.00)))
        #expect(rule.matches(payee: "Mid Range", account: account, amount: Decimal(50.00)))
        #expect(!rule.matches(payee: "Too Small", account: account, amount: Decimal(9.99)))
        #expect(!rule.matches(payee: "Too Large", account: account, amount: Decimal(50.01)))
    }

    // MARK: - Account Matching Tests

    @Test func testAccountMatching() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account1, _, _) = createTestData(context: context)

        let account2 = Account(name: "Other Account", type: .savings, balance: 500)
        context.insert(account2)
        try! context.save()

        let rule = AutoRule(name: "Test Rule")
        rule.matchAccount = account1
        context.insert(rule)

        #expect(rule.matches(payee: "Test", account: account1, amount: Decimal(10.00)))
        #expect(!rule.matches(payee: "Test", account: account2, amount: Decimal(10.00)))
        #expect(!rule.matches(payee: "Test", account: nil, amount: Decimal(10.00)))
    }

    // MARK: - Rule Application Tests

    @Test func testApplyRuleRenamePayee() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "AMZN*234JKL",
            amount: Decimal(-25.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule = AutoRule(name: "Clean Amazon Names")
        rule.matchPayeeCondition = .startsWith
        rule.matchPayeeValue = "AMZN"
        rule.actionRenamePayee = "Amazon"
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.payee == "Amazon")
        #expect(result.fieldsChanged.contains(.payee))
    }

    @Test func testApplyRuleSetCategory() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, category, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Grocery Store",
            amount: Decimal(-50.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule = AutoRule(name: "Categorize Groceries")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Grocery"
        rule.actionCategory = category
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.category?.name == "Test Category")
        #expect(result.fieldsChanged.contains(.category))
    }

    @Test func testApplyRuleSetTags() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, tags) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Business Expense",
            amount: Decimal(-100.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule = AutoRule(name: "Tag Business")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Business"
        rule.actionTags = tags
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.tags?.count == 2)
        #expect(result.fieldsChanged.contains(.tags))
    }

    @Test func testApplyRuleSetMemo() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Subscription Service",
            amount: Decimal(-9.99),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule = AutoRule(name: "Add Memo")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Subscription"
        rule.actionMemo = "Monthly subscription"
        rule.actionAppendMemo = false
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.memo == "Monthly subscription")
        #expect(result.fieldsChanged.contains(.memo))
    }

    @Test func testApplyRuleAppendMemo() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Store",
            amount: Decimal(-20.00),
            kind: .standard,
            account: account
        )
        transaction.memo = "Original memo"
        context.insert(transaction)

        let rule = AutoRule(name: "Append Note")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Store"
        rule.actionMemo = "Needs review"
        rule.actionAppendMemo = true
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.memo == "Original memo | Needs review")
        #expect(result.fieldsChanged.contains(.memo))
    }

    @Test func testApplyRuleSetStatus() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Paycheck",
            amount: Decimal(5000.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule = AutoRule(name: "Mark Income")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Paycheck"
        rule.actionStatus = .cleared
        context.insert(rule)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 1)
        #expect(transaction.status == .cleared)
        #expect(result.fieldsChanged.contains(.status))
    }

    @Test func testApplyMultipleRules() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, category, tags) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Amazon Purchase",
            amount: Decimal(-99.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        let rule1 = AutoRule(name: "Rule 1", order: 0)
        rule1.matchPayeeCondition = .contains
        rule1.matchPayeeValue = "Amazon"
        rule1.actionRenamePayee = "Amazon"
        context.insert(rule1)

        let rule2 = AutoRule(name: "Rule 2", order: 1)
        rule2.matchPayeeCondition = .equals
        rule2.matchPayeeValue = "Amazon"
        rule2.actionCategory = category
        rule2.actionTags = tags
        context.insert(rule2)

        let result = service.applyRules(to: transaction)

        #expect(result.rulesApplied.count == 2)
        #expect(transaction.payee == "Amazon")
        #expect(transaction.category?.name == "Test Category")
        #expect(transaction.tags?.count == 2)
    }

    @Test func testRuleStatisticsUpdated() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Test"
        rule.actionRenamePayee = "TestCo"
        context.insert(rule)

        let initialCount = rule.timesApplied
        let initialDate = rule.lastAppliedAt

        let transaction = Transaction(
            date: Date(),
            payee: "Test Store",
            amount: Decimal(-10.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        _ = service.applyRules(to: transaction)

        #expect(rule.timesApplied == initialCount + 1)
        #expect(rule.lastAppliedAt != initialDate)
        #expect(rule.lastAppliedAt != nil)
    }

    @Test func testPreviewMatchingTransactions() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        for i in 1...10 {
            let transaction = Transaction(
                date: Date().addingTimeInterval(Double(-i * 86400)),
                payee: i <= 5 ? "Amazon \(i)" : "Walmart \(i)",
                amount: Decimal(-Double(i * 10)),
                kind: .standard,
                account: account
            )
            context.insert(transaction)
        }
        try! context.save()

        let rule = AutoRule(name: "Amazon Rule")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Amazon"
        context.insert(rule)

        let matches = service.previewMatchingTransactions(for: rule, limit: 10)

        #expect(matches.count == 5)
        #expect(matches.allSatisfy { $0.payee.contains("Amazon") })
    }

    @Test func testRuleDeletion() {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _, _) = createTestData(context: context)
        let service = AutoRulesService(modelContext: context)

        let rule = AutoRule(name: "Test Rule")
        rule.matchPayeeCondition = .contains
        rule.matchPayeeValue = "Test"
        rule.actionRenamePayee = "TestCo"
        context.insert(rule)

        let transaction = Transaction(
            date: Date(),
            payee: "Test Store",
            amount: Decimal(-10.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)

        _ = service.applyRules(to: transaction)
        try! context.save()

        let applications = service.fetchApplications(for: rule, limit: 10)
        #expect(applications.count == 1)

        service.deleteRule(rule)
        try! context.save()

        let descriptor = FetchDescriptor<AutoRule>()
        let rules = try! context.fetch(descriptor)
        #expect(rules.isEmpty)

        let appDescriptor = FetchDescriptor<AutoRuleApplication>()
        let apps = try! context.fetch(appDescriptor)
        #expect(apps.isEmpty)
    }

    @Test func testRuleReordering() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = AutoRulesService(modelContext: context)

        let rule1 = AutoRule(name: "Rule 1", order: 0)
        let rule2 = AutoRule(name: "Rule 2", order: 1)
        let rule3 = AutoRule(name: "Rule 3", order: 2)

        context.insert(rule1)
        context.insert(rule2)
        context.insert(rule3)
        try! context.save()

        service.reorderRules([rule3, rule1, rule2])

        #expect(rule3.order == 0)
        #expect(rule1.order == 1)
        #expect(rule2.order == 2)
    }

    @Test func testNextRuleOrder() {
        let container = createTestContainer()
        let context = container.mainContext
        let service = AutoRulesService(modelContext: context)

        let nextOrder1 = service.nextRuleOrder()
        #expect(nextOrder1 == 0)

        let rule1 = AutoRule(name: "Rule 1", order: 0)
        context.insert(rule1)
        try! context.save()

        let nextOrder2 = service.nextRuleOrder()
        #expect(nextOrder2 == 1)

        let rule2 = AutoRule(name: "Rule 2", order: 5)
        context.insert(rule2)
        try! context.save()

        let nextOrder3 = service.nextRuleOrder()
        #expect(nextOrder3 == 6)
    }
}
