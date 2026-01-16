import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

@MainActor
struct TransferLinkerTests {

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

    private func createTestAccounts(context: ModelContext) -> (checking: Account, savings: Account) {
        let checking = Account(name: "Checking", type: .chequing, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 5000)

        context.insert(checking)
        context.insert(savings)
        try! context.save()

        return (checking, savings)
    }

    // MARK: - Candidate Matching Tests

    @Test func testCandidateMatchesWithOppositeAmount() {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let baseTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(baseTransaction)

        let matchingTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: savings
        )
        context.insert(matchingTransaction)

        let nonMatchingTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(50.00),
            kind: .standard,
            account: savings
        )
        context.insert(nonMatchingTransaction)

        try! context.save()

        let candidates = TransferLinker.candidateMatches(
            for: baseTransaction,
            modelContext: context,
            window: .all
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.amount == Decimal(-100.00))
        #expect(candidates.first?.account?.name == "Savings")
    }

    @Test func testCandidateMatchesExcludesSameAccount() {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let baseTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(baseTransaction)

        let sameAccountTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        context.insert(sameAccountTransaction)

        try! context.save()

        let candidates = TransferLinker.candidateMatches(
            for: baseTransaction,
            modelContext: context,
            window: .all
        )

        #expect(candidates.isEmpty)
    }

    @Test func testCandidateMatchesExcludesAlreadyLinked() {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let baseTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(baseTransaction)

        let linkedTransaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: savings
        )
        linkedTransaction.transferID = UUID()
        context.insert(linkedTransaction)

        try! context.save()

        let candidates = TransferLinker.candidateMatches(
            for: baseTransaction,
            modelContext: context,
            window: .all
        )

        #expect(candidates.isEmpty)
    }

    @Test func testCandidateMatchesWithTimeWindow() {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let baseDate = Date()
        let baseTransaction = Transaction(
            date: baseDate,
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(baseTransaction)

        let recentTransaction = Transaction(
            date: baseDate.addingTimeInterval(-30 * 24 * 60 * 60),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: savings
        )
        context.insert(recentTransaction)

        let oldTransaction = Transaction(
            date: baseDate.addingTimeInterval(-100 * 24 * 60 * 60),
            payee: "Old Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: savings
        )
        context.insert(oldTransaction)

        try! context.save()

        let candidates = TransferLinker.candidateMatches(
            for: baseTransaction,
            modelContext: context,
            window: .days(90)
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.payee == "Transfer")
    }

    @Test func testCandidateMatchesSortedByDate() {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let baseDate = Date()
        let baseTransaction = Transaction(
            date: baseDate,
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(baseTransaction)

        let closeTransaction = Transaction(
            date: baseDate.addingTimeInterval(-1 * 24 * 60 * 60),
            payee: "Close Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: savings
        )
        context.insert(closeTransaction)

        let farTransaction = Transaction(
            date: baseDate.addingTimeInterval(-10 * 24 * 60 * 60),
            payee: "Far Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: savings
        )
        context.insert(farTransaction)

        try! context.save()

        let candidates = TransferLinker.candidateMatches(
            for: baseTransaction,
            modelContext: context,
            window: .all
        )

        #expect(candidates.count == 2)
        #expect(candidates.first?.payee == "Close Transfer")
        #expect(candidates.last?.payee == "Far Transfer")
    }

    // MARK: - Transfer Linking Tests

    @Test func testLinkAsTransferSuccess() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)
        let category = EscapeBudget.Category(name: "Test Category")
        category.group = group
        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        context.insert(category)

        let transaction1 = Transaction(
            date: Date(),
            payee: "Transfer to Savings",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        transaction1.category = category
        context.insert(transaction1)

        let transaction2 = Transaction(
            date: Date(),
            payee: "Transfer from Checking",
            amount: Decimal(100.00),
            kind: .standard,
            account: savings
        )
        context.insert(transaction2)

        try! context.save()

        try TransferLinker.linkAsTransfer(
            base: transaction1,
            match: transaction2,
            modelContext: context
        )

        #expect(transaction1.kind == .transfer)
        #expect(transaction2.kind == .transfer)
        #expect(transaction1.transferID != nil)
        #expect(transaction2.transferID != nil)
        #expect(transaction1.transferID == transaction2.transferID)
        #expect(transaction1.category == nil)
        #expect(transaction2.category == nil)
    }

    @Test func testLinkAsTransferCreatesHistoryEntries() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let transaction1 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        context.insert(transaction1)

        let transaction2 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: savings
        )
        context.insert(transaction2)

        try! context.save()

        try TransferLinker.linkAsTransfer(
            base: transaction1,
            match: transaction2,
            modelContext: context
        )

        let descriptor = FetchDescriptor<TransactionHistoryEntry>()
        let entries = try! context.fetch(descriptor)

        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.detail.contains("Converted to Transfer") })
    }

    @Test func testLinkAsTransferFailsWhenAlreadyLinked() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let transaction1 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: checking
        )
        transaction1.transferID = UUID()
        context.insert(transaction1)

        let transaction2 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: savings
        )
        context.insert(transaction2)

        try! context.save()

        #expect(throws: Error.self) {
            try TransferLinker.linkAsTransfer(
                base: transaction1,
                match: transaction2,
                modelContext: context
            )
        }
    }

    @Test func testLinkAsTransferFailsWithMismatchedAmounts() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, savings) = createTestAccounts(context: context)

        let transaction1 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        context.insert(transaction1)

        let transaction2 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(50.00),
            kind: .standard,
            account: savings
        )
        context.insert(transaction2)

        try! context.save()

        #expect(throws: Error.self) {
            try TransferLinker.linkAsTransfer(
                base: transaction1,
                match: transaction2,
                modelContext: context
            )
        }
    }

    @Test func testLinkAsTransferFailsWithSameAccount() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction1 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        context.insert(transaction1)

        let transaction2 = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(100.00),
            kind: .standard,
            account: checking
        )
        context.insert(transaction2)

        try! context.save()

        #expect(throws: Error.self) {
            try TransferLinker.linkAsTransfer(
                base: transaction1,
                match: transaction2,
                modelContext: context
            )
        }
    }

    // MARK: - Mark Unmatched Transfer Tests

    @Test func testMarkUnmatchedTransfer() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)
        let category = EscapeBudget.Category(name: "Test Category")
        category.group = group
        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        context.insert(category)

        let transaction = Transaction(
            date: Date(),
            payee: "One-sided Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        transaction.category = category
        context.insert(transaction)

        try! context.save()

        try TransferLinker.markUnmatchedTransfer(transaction, modelContext: context)

        #expect(transaction.kind == .transfer)
        #expect(transaction.transferID == nil)
        #expect(transaction.category == nil)
    }

    @Test func testMarkUnmatchedTransferCreatesHistory() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .standard,
            account: checking
        )
        context.insert(transaction)

        try! context.save()

        try TransferLinker.markUnmatchedTransfer(transaction, modelContext: context)

        let descriptor = FetchDescriptor<TransactionHistoryEntry>()
        let entries = try! context.fetch(descriptor)

        #expect(entries.count == 1)
        #expect(entries.first?.detail.contains("Marked as Transfer (unmatched)") == true)
    }

    @Test func testMarkUnmatchedTransferFailsWhenAlreadyLinked() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: checking
        )
        transaction.transferID = UUID()
        context.insert(transaction)

        try! context.save()

        #expect(throws: Error.self) {
            try TransferLinker.markUnmatchedTransfer(transaction, modelContext: context)
        }
    }

    // MARK: - Convert to Standard Tests

    @Test func testConvertToStandard() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: checking
        )
        context.insert(transaction)

        try! context.save()

        try TransferLinker.convertToStandard(transaction, modelContext: context)

        #expect(transaction.kind == .standard)
        #expect(transaction.category == nil)
    }

    @Test func testConvertToStandardCreatesHistory() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: checking
        )
        context.insert(transaction)

        try! context.save()

        try TransferLinker.convertToStandard(transaction, modelContext: context)

        let descriptor = FetchDescriptor<TransactionHistoryEntry>()
        let entries = try! context.fetch(descriptor)

        #expect(entries.count == 1)
        #expect(entries.first?.detail.contains("Converted from Transfer back to Standard") == true)
    }

    @Test func testConvertToStandardFailsWhenLinked() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let (checking, _) = createTestAccounts(context: context)

        let transaction = Transaction(
            date: Date(),
            payee: "Transfer",
            amount: Decimal(-100.00),
            kind: .transfer,
            account: checking
        )
        transaction.transferID = UUID()
        context.insert(transaction)

        try! context.save()

        #expect(throws: Error.self) {
            try TransferLinker.convertToStandard(transaction, modelContext: context)
        }
    }

    // MARK: - Search Window Tests

    @Test func testSearchWindowDaysCalculation() {
        let window30 = TransferLinker.SearchWindow.days(30)
        let window90 = TransferLinker.SearchWindow.days(90)
        let windowAll = TransferLinker.SearchWindow.all

        #expect(window30.maxInterval == TimeInterval(30 * 24 * 60 * 60))
        #expect(window90.maxInterval == TimeInterval(90 * 24 * 60 * 60))
        #expect(windowAll.maxInterval == nil)
    }

    @Test func testSearchWindowHashable() {
        let window1 = TransferLinker.SearchWindow.days(30)
        let window2 = TransferLinker.SearchWindow.days(30)
        let window3 = TransferLinker.SearchWindow.days(90)
        let windowAll = TransferLinker.SearchWindow.all

        var set = Set<TransferLinker.SearchWindow>()
        set.insert(window1)
        set.insert(window2)
        set.insert(window3)
        set.insert(windowAll)

        #expect(set.count == 3)
    }
}
