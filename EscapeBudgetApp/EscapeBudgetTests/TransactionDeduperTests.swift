import Testing
import Foundation
@testable import EscapeBudget

struct TransactionDeduperTests {

    @Test("TransactionDeduper: Not duplicate when different day")
    func testDifferentDayNotDuplicate() {
        let existing = Transaction(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            payee: "Coffee Shop",
            amount: -4.50
        )

        let imported = ImportedTransaction(
            date: Date(timeIntervalSince1970: 1_700_000_000 + 86_400),
            payee: "Coffee Shop",
            amount: -4.50
        )

        let result = TransactionDeduper.evaluate(
            imported: imported,
            existing: existing,
            config: .init(useNormalizedPayee: true, similarityThreshold: 0.85)
        )

        #expect(result.isDuplicate == false)
    }

    @Test("TransactionDeduper: Not duplicate when amount differs")
    func testDifferentAmountNotDuplicate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = Transaction(date: date, payee: "Coffee Shop", amount: -4.50)
        let imported = ImportedTransaction(date: date, payee: "Coffee Shop", amount: -4.51)

        let result = TransactionDeduper.evaluate(
            imported: imported,
            existing: existing,
            config: .init(useNormalizedPayee: true, similarityThreshold: 0.85)
        )

        #expect(result.isDuplicate == false)
    }

    @Test("TransactionDeduper: Duplicate on exact payee match (normalized)")
    func testExactPayeeMatchDuplicate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let existing = Transaction(
            date: date,
            payee: "STARBUCKS #1234",
            amount: -5.75
        )

        var imported = ImportedTransaction(
            date: date,
            payee: "Starbucks 1234",
            amount: -5.75
        )
        imported.rawPayee = "Starbucks   #1234"

        let result = TransactionDeduper.evaluate(
            imported: imported,
            existing: existing,
            config: .init(useNormalizedPayee: true, similarityThreshold: 0.95)
        )

        #expect(result.isDuplicate == true)
        #expect(result.reason != nil)
    }

    @Test("TransactionDeduper: Duplicate on memo match when payee differs")
    func testMemoMatchDuplicate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let existing = Transaction(
            date: date,
            payee: "Merchant A",
            amount: -12.34,
            memo: "Order 98765"
        )

        let imported = ImportedTransaction(
            date: date,
            payee: "Completely Different Merchant",
            amount: -12.34,
            memo: "Order 98765"
        )

        let result = TransactionDeduper.evaluate(
            imported: imported,
            existing: existing,
            config: .init(useNormalizedPayee: false, similarityThreshold: 0.99)
        )

        #expect(result.isDuplicate == true)
        #expect(result.reason == "Memo match")
    }
}

