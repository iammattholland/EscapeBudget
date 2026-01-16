import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

@MainActor
struct CommandServicesTests {

    // MARK: - Test Setup

    private func createTestContainer() -> ModelContainer {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            TransactionTag.self,
            CategoryGroup.self,
            TransactionHistoryEntry.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }

    private func createTestData(context: ModelContext) -> (account: Account, category: EscapeBudget.Category) {
        let account = Account(name: "Test Account", type: .chequing, balance: 1000)
        context.insert(account)

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)

        let category = EscapeBudget.Category(name: "Test Category")
        category.group = group
        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        context.insert(category)

        try! context.save()

        return (account, category)
    }

    // MARK: - Transaction Command Tests

    @Test func testAddTransactionCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, category) = createTestData(context: context)

        let command = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test Payee",
            amount: Decimal(-50.00),
            memo: "Test memo",
            status: .cleared,
            kind: .standard,
            account: account,
            category: category
        )

        try command.execute()

        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try context.fetch(descriptor)

        #expect(transactions.count == 1)
        #expect(transactions.first?.payee == "Test Payee")
        #expect(transactions.first?.amount == Decimal(-50.00))
        #expect(transactions.first?.memo == "Test memo")
        #expect(transactions.first?.status == .cleared)
        #expect(transactions.first?.account?.name == "Test Account")
        #expect(transactions.first?.category?.name == "Test Category")
    }

    @Test func testAddTransactionCommandUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let command = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test Payee",
            amount: Decimal(-50.00),
            account: account
        )

        try command.execute()

        var descriptor = FetchDescriptor<Transaction>()
        var transactions = try context.fetch(descriptor)
        #expect(transactions.count == 1)

        try command.undo()

        descriptor = FetchDescriptor<Transaction>()
        transactions = try context.fetch(descriptor)
        #expect(transactions.isEmpty)
    }

    @Test func testDeleteTransactionCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, category) = createTestData(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Test Payee",
            amount: Decimal(-50.00),
            kind: .standard,
            account: account
        )
        transaction.category = category
        transaction.memo = "Test memo"
        context.insert(transaction)
        try context.save()

        let command = DeleteTransactionCommand(
            modelContext: context,
            transaction: transaction
        )

        try command.execute()

        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try context.fetch(descriptor)
        #expect(transactions.isEmpty)
    }

    @Test func testDeleteTransactionCommandUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, category) = createTestData(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Test Payee",
            amount: Decimal(-50.00),
            kind: .standard,
            account: account
        )
        transaction.category = category
        transaction.memo = "Test memo"
        context.insert(transaction)
        try context.save()

        let command = DeleteTransactionCommand(
            modelContext: context,
            transaction: transaction
        )

        try command.execute()

        var descriptor = FetchDescriptor<Transaction>()
        var transactions = try context.fetch(descriptor)
        #expect(transactions.isEmpty)

        try command.undo()

        descriptor = FetchDescriptor<Transaction>()
        transactions = try context.fetch(descriptor)
        #expect(transactions.count == 1)
        #expect(transactions.first?.payee == "Test Payee")
        #expect(transactions.first?.amount == Decimal(-50.00))
        #expect(transactions.first?.memo == "Test memo")
        #expect(transactions.first?.category?.name == "Test Category")
    }

    // MARK: - Account Command Tests

    @Test func testAddAccountCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let command = AddAccountCommand(
            modelContext: context,
            name: "New Account",
            type: .savings,
            balance: Decimal(5000.00)
        )

        try command.execute()

        let descriptor = FetchDescriptor<Account>()
        let accounts = try context.fetch(descriptor)

        #expect(accounts.count == 1)
        #expect(accounts.first?.name == "New Account")
        #expect(accounts.first?.type == .savings)
        #expect(accounts.first?.balance == Decimal(5000.00))
    }

    @Test func testAddAccountCommandUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let command = AddAccountCommand(
            modelContext: context,
            name: "New Account",
            type: .savings,
            balance: Decimal(5000.00)
        )

        try command.execute()

        var descriptor = FetchDescriptor<Account>()
        var accounts = try context.fetch(descriptor)
        #expect(accounts.count == 1)

        try command.undo()

        descriptor = FetchDescriptor<Account>()
        accounts = try context.fetch(descriptor)
        #expect(accounts.isEmpty)
    }

    @Test func testUpdateAccountCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Old Name", type: .chequing, balance: 1000)
        context.insert(account)
        try context.save()

        let command = UpdateAccountCommand(
            modelContext: context,
            account: account,
            newName: "New Name",
            newType: .savings,
            newBalance: Decimal(2000.00),
            newNotes: nil
        )

        try command.execute()

        #expect(account.name == "New Name")
        #expect(account.type == .savings)
        #expect(account.balance == Decimal(2000.00))
    }

    @Test func testUpdateAccountCommandUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Old Name", type: .chequing, balance: 1000)
        context.insert(account)
        try context.save()

        let command = UpdateAccountCommand(
            modelContext: context,
            account: account,
            newName: "New Name",
            newType: .savings,
            newBalance: Decimal(2000.00),
            newNotes: nil
        )

        try command.execute()

        #expect(account.name == "New Name")
        #expect(account.type == .savings)

        try command.undo()

        #expect(account.name == "Old Name")
        #expect(account.type == .chequing)
        #expect(account.balance == Decimal(1000.00))
    }

    // MARK: - Category Command Tests

    @Test func testAddCategoryCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)
        try context.save()

        let command = AddCategoryCommand(
            modelContext: context,
            name: "New Category",
            group: group
        )

        try command.execute()

        let descriptor = FetchDescriptor<EscapeBudget.Category>()
        let categories = try context.fetch(descriptor)

        #expect(categories.count == 1)
        #expect(categories.first?.name == "New Category")
        #expect(categories.first?.group?.name == "Test Group")
    }

    @Test func testAddCategoryCommandUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)
        try context.save()

        let command = AddCategoryCommand(
            modelContext: context,
            name: "New Category",
            group: group
        )

        try command.execute()

        var descriptor = FetchDescriptor<EscapeBudget.Category>()
        var categories = try context.fetch(descriptor)
        #expect(categories.count == 1)

        try command.undo()

        descriptor = FetchDescriptor<EscapeBudget.Category>()
        categories = try context.fetch(descriptor)
        #expect(categories.isEmpty)
    }

    // MARK: - UndoRedo Manager Integration Tests

    @Test func testUndoRedoManagerExecute() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        let command = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test",
            amount: Decimal(-10.00),
            account: account
        )

        try manager.execute(command)

        #expect(manager.canUndo)
        #expect(!manager.canRedo)

        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try context.fetch(descriptor)
        #expect(transactions.count == 1)
    }

    @Test func testUndoRedoManagerUndo() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        let command = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test",
            amount: Decimal(-10.00),
            account: account
        )

        try manager.execute(command)
        #expect(manager.canUndo)

        try manager.undo()

        #expect(!manager.canUndo)
        #expect(manager.canRedo)

        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try context.fetch(descriptor)
        #expect(transactions.isEmpty)
    }

    @Test func testUndoRedoManagerRedo() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        let command = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test",
            amount: Decimal(-10.00),
            account: account
        )

        try manager.execute(command)
        try manager.undo()

        #expect(manager.canRedo)

        try manager.redo()

        #expect(manager.canUndo)
        #expect(!manager.canRedo)

        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try context.fetch(descriptor)
        #expect(transactions.count == 1)
    }

    @Test func testUndoRedoManagerMultipleCommands() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        let command1 = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Transaction 1",
            amount: Decimal(-10.00),
            account: account
        )

        let command2 = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Transaction 2",
            amount: Decimal(-20.00),
            account: account
        )

        try manager.execute(command1)
        try manager.execute(command2)

        var descriptor = FetchDescriptor<Transaction>()
        var transactions = try context.fetch(descriptor)
        #expect(transactions.count == 2)

        try manager.undo()

        descriptor = FetchDescriptor<Transaction>()
        transactions = try context.fetch(descriptor)
        #expect(transactions.count == 1)
        #expect(transactions.first?.payee == "Transaction 1")

        try manager.undo()

        descriptor = FetchDescriptor<Transaction>()
        transactions = try context.fetch(descriptor)
        #expect(transactions.isEmpty)
    }

    @Test func testUndoRedoManagerClearsRedoStackOnNewCommand() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        let command1 = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Transaction 1",
            amount: Decimal(-10.00),
            account: account
        )

        let command2 = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Transaction 2",
            amount: Decimal(-20.00),
            account: account
        )

        try manager.execute(command1)
        try manager.undo()

        #expect(manager.canRedo)

        try manager.execute(command2)

        #expect(!manager.canRedo)
        #expect(manager.canUndo)
    }

    @Test func testUndoRedoManagerMaxStackSize() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let manager = UndoRedoManager()

        for i in 1...60 {
            let command = AddTransactionCommand(
                modelContext: context,
                date: Date(),
                payee: "Transaction \(i)",
                amount: Decimal(-Double(i)),
                account: account
            )
            try manager.execute(command)
        }

        var undoCount = 0
        while manager.canUndo {
            try manager.undo()
            undoCount += 1
        }

        #expect(undoCount <= 50)
    }

    // MARK: - Command Description Tests

    @Test func testCommandDescriptions() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (account, _) = createTestData(context: context)

        let addCommand = AddTransactionCommand(
            modelContext: context,
            date: Date(),
            payee: "Test Payee",
            amount: Decimal(-10.00),
            account: account
        )

        #expect(addCommand.description.contains("Test Payee"))

        let accountCommand = AddAccountCommand(
            modelContext: context,
            name: "New Account",
            type: .savings,
            balance: 0
        )

        #expect(accountCommand.description.contains("New Account"))
    }
}
