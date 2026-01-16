import Testing
import Foundation
@testable import EscapeBudget

struct TransactionParserTests {
    
    // MARK: - CSV Parsing Tests
    
    @Test func testParseCSVBasic() async throws {
        // Create a temporary CSV file for testing
        let csvContent = """
        Date,Payee,Amount
        12/25/2024,Grocery Store,-50.00
        12/26/2024,Direct Deposit,2000.00
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let parser = TransactionParser()
        let result = try await parser.parse(url: tempURL)
        
        #expect(result.rows.count == 3) // Header + 2 data rows
        #expect(result.fileName == "test.csv")
        #expect(result.rows[0].contains("Date"))
        #expect(result.rows[1].contains("Grocery Store"))
    }
    
    @Test func testParseCSVWithQuotes() async throws {
        // CSV with quoted fields containing commas
        let csvContent = """
        Date,Payee,Amount
        12/25/2024,"Smith, John",-100.00
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_quotes.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let parser = TransactionParser()
        let result = try await parser.parse(url: tempURL)
        
        #expect(result.rows.count == 2)
        #expect(result.rows[1][1] == "Smith, John")
        #expect(result.rows[1][2] == "-100.00")
    }
    
    @Test func testParseCSVWithWindowsLineEndings() async throws {
        let csvContent = "Date,Payee,Amount\r\n01/01/2024,Store A,-10.00\r\n01/02/2024,Store B,20.00"
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("windows.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let parser = TransactionParser()
        let result = try await parser.parse(url: tempURL)
        
        #expect(result.rows.count == 3)
        #expect(result.rows[1][0] == "01/01/2024")
        #expect(result.rows[2][1] == "Store B")
    }
    
    @Test func testParseCSVEmptyFile() async throws {
        let csvContent = ""
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let parser = TransactionParser()
        let result = try await parser.parse(url: tempURL)
        
        #expect(result.rows.isEmpty)
    }
    
    @Test func testParseCSVWithDifferentAmountFormats() async throws {
        let csvContent = """
        Date,Payee,Amount
        12/25/2024,Store A,$1,234.56
        12/26/2024,Store B,(500.00)
        12/27/2024,Store C,-75.50
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("amounts.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let parser = TransactionParser()
        let result = try await parser.parse(url: tempURL)
        
        #expect(result.rows.count == 4)
    }
    
    // MARK: - ParsedFile Tests
    
    @Test func testParsedFileStructure() throws {
        let rows = [
            ["Date", "Payee", "Amount"],
            ["12/25/2024", "Test", "-50.00"]
        ]
        
        let parsedFile = ParsedFile(rows: rows, fileName: "test.csv")
        
        #expect(parsedFile.fileName == "test.csv")
        #expect(parsedFile.rows.count == 2)
        #expect(parsedFile.rows[0].count == 3)
    }
}
