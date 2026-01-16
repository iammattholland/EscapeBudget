import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

@MainActor
struct TransactionExporterTests {

    // MARK: - Test Setup

    private func createTestContainer() -> ModelContainer {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            TransactionTag.self,
            CategoryGroup.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }

    private func createTestTransactions(context: ModelContext) -> [Transaction] {
        let account = Account(name: "Test Account", type: .chequing, balance: 1000)
        context.insert(account)

        let group = CategoryGroup(name: "Test Group")
        context.insert(group)

        let category = Category(name: "Groceries")
        category.group = group
        if group.categories == nil { group.categories = [] }
        group.categories?.append(category)
        context.insert(category)

        let tag1 = TransactionTag(name: "Tag1", colorHex: "#007AFF")
        let tag2 = TransactionTag(name: "Tag2", colorHex: "#34C759")
        context.insert(tag1)
        context.insert(tag2)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let transaction1 = Transaction(
            date: dateFormatter.date(from: "2024-01-15")!,
            payee: "Grocery Store",
            amount: Decimal(-50.00),
            kind: .standard,
            account: account
        )
        transaction1.category = category
        transaction1.tags = [tag1, tag2]
        transaction1.memo = "Weekly groceries"
        transaction1.status = .cleared

        let transaction2 = Transaction(
            date: dateFormatter.date(from: "2024-01-20")!,
            payee: "Paycheck",
            amount: Decimal(2000.00),
            kind: .standard,
            account: account
        )
        transaction2.status = .cleared

        let transaction3 = Transaction(
            date: dateFormatter.date(from: "2024-01-25")!,
            payee: "Special,\"Characters\"",
            amount: Decimal(-25.50),
            kind: .standard,
            account: account
        )
        transaction3.memo = "Contains\nNewline"

        context.insert(transaction1)
        context.insert(transaction2)
        context.insert(transaction3)

        try! context.save()

        return [transaction1, transaction2, transaction3]
    }

    // MARK: - Standard Format Tests

    @Test func testExportStandardFormatHeaders() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let headers = lines[0]

        #expect(headers.contains("Date"))
        #expect(headers.contains("Payee"))
        #expect(headers.contains("Memo"))
        #expect(headers.contains("Amount"))
        #expect(headers.contains("Account"))
        #expect(headers.contains("Category"))
        #expect(headers.contains("Tags"))
        #expect(headers.contains("Status"))
    }

    @Test func testExportStandardFormatData() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")

        #expect(lines.count >= 4)
        #expect(lines[1].contains("Grocery Store"))
        #expect(lines[1].contains("-50"))
        #expect(lines[1].contains("Groceries"))
        #expect(lines[1].contains("Cleared"))
    }

    @Test func testExportStandardFormatMultipleTags() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let firstDataLine = lines[1]

        #expect(firstDataLine.contains("Tag1"))
        #expect(firstDataLine.contains("Tag2"))
        #expect(firstDataLine.contains(";"))
    }

    // MARK: - YNAB Format Tests

    @Test func testExportYNABFormatHeaders() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .ynab)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let headers = lines[0]

        #expect(headers.contains("Date"))
        #expect(headers.contains("Payee"))
        #expect(headers.contains("Category"))
        #expect(headers.contains("Memo"))
        #expect(headers.contains("Outflow"))
        #expect(headers.contains("Inflow"))
    }

    @Test func testExportYNABFormatSeparatesInflowOutflow() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .ynab)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")

        let expenseLine = lines[1]
        let incomeLine = lines[2]

        #expect(expenseLine.contains("50"))
        #expect(!incomeLine.contains("-"))
        #expect(incomeLine.contains("2000"))
    }

    // MARK: - Mint Format Tests

    @Test func testExportMintFormatHeaders() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .mint)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let headers = lines[0]

        #expect(headers.contains("Date"))
        #expect(headers.contains("Description"))
        #expect(headers.contains("Original Description"))
        #expect(headers.contains("Amount"))
        #expect(headers.contains("Transaction Type"))
        #expect(headers.contains("Category"))
        #expect(headers.contains("Account Name"))
        #expect(headers.contains("Labels"))
        #expect(headers.contains("Notes"))
    }

    @Test func testExportMintFormatTransactionTypes() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .mint)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")

        let expenseLine = lines[1]
        let incomeLine = lines[2]

        #expect(expenseLine.contains("debit"))
        #expect(incomeLine.contains("credit"))
    }

    // MARK: - CSV Escaping Tests

    @Test func testCSVEscapingCommas() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let specialLine = lines[3]

        #expect(specialLine.contains("\"Special,\"\"Characters\"\"\""))
    }

    @Test func testCSVEscapingNewlines() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        #expect(csvString.contains("\"Contains\nNewline\""))
    }

    @Test func testCSVInjectionPrevention() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let dangerousPayees = [
            "=1+1",
            "+1+1",
            "-1+1",
            "@SUM(A1:A10)",
            "\t1+1",
            "\r1+1"
        ]

        var transactions: [Transaction] = []
        for payee in dangerousPayees {
            let tx = Transaction(
                date: Date(),
                payee: payee,
                amount: Decimal(-10.00),
                kind: .standard,
                account: account
            )
            context.insert(tx)
            transactions.append(tx)
        }

        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        for payee in dangerousPayees {
            #expect(csvString.contains("'\(payee)"))
        }
    }

    // MARK: - Date Formatting Tests

    @Test func testDateFormattingConsistency() {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData(transactions, format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let firstDataLine = lines[1]

        #expect(firstDataLine.contains("01/15/2024"))
    }

    // MARK: - Empty Data Tests

    @Test func testExportEmptyTransactionList() {
        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")

        #expect(lines.count >= 1)
        #expect(lines[0].contains("Date"))
    }

    @Test func testExportTransactionWithNoCategory() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let transaction = Transaction(
            date: Date(),
            payee: "No Category",
            amount: Decimal(-10.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)
        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([transaction], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        #expect(!csvString.isEmpty)
        #expect(csvString.contains("No Category"))
    }

    @Test func testExportTransactionWithNoMemo() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let transaction = Transaction(
            date: Date(),
            payee: "No Memo",
            amount: Decimal(-10.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)
        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([transaction], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        let lines = csvString.components(separatedBy: "\n")
        let fields = lines[1].components(separatedBy: ",")

        #expect(fields.contains(""))
    }

    @Test func testExportTransactionWithNoTags() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let transaction = Transaction(
            date: Date(),
            payee: "No Tags",
            amount: Decimal(-10.00),
            kind: .standard,
            account: account
        )
        context.insert(transaction)
        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([transaction], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        #expect(!csvString.isEmpty)
    }

    // MARK: - Decimal Precision Tests

    @Test func testDecimalPrecisionPreserved() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let transaction = Transaction(
            date: Date(),
            payee: "Precise Amount",
            amount: Decimal(string: "123.456789")!,
            kind: .standard,
            account: account
        )
        context.insert(transaction)
        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([transaction], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        #expect(csvString.contains("123.456789"))
    }

    @Test func testNegativeAmountsFormattedCorrectly() {
        let container = createTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", type: .chequing, balance: 0)
        context.insert(account)

        let transaction = Transaction(
            date: Date(),
            payee: "Expense",
            amount: Decimal(-100.50),
            kind: .standard,
            account: account
        )
        context.insert(transaction)
        try! context.save()

        let exporter = TransactionExporter()
        let data = exporter.exportCSVData([transaction], format: .standard)
        let csvString = String(data: data, encoding: .utf8)!

        #expect(csvString.contains("-100.5"))
    }

    // MARK: - File Writing Tests

    @Test func testExportToFileURL() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_export.csv")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let exporter = TransactionExporter()
        try exporter.exportTransactions(transactions, to: fileURL, format: .standard)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(fileContent.contains("Grocery Store"))
        #expect(fileContent.contains("Paycheck"))
    }

    @Test func testExportOverwritesExistingFile() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_overwrite.csv")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        try "Old Content".write(to: fileURL, atomically: true, encoding: .utf8)

        let exporter = TransactionExporter()
        try exporter.exportTransactions(transactions, to: fileURL, format: .standard)

        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!fileContent.contains("Old Content"))
        #expect(fileContent.contains("Grocery Store"))
    }

    // MARK: - Legacy Method Tests

    @Test func testLegacyExportMethod() throws {
        let container = createTestContainer()
        let context = container.mainContext
        let transactions = createTestTransactions(context: context)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_legacy.csv")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let exporter = TransactionExporter()
        try exporter.exportTransactions(transactions, to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(fileContent.contains("Date,Payee,Memo"))
        #expect(fileContent.contains("Grocery Store"))
    }
}
