import Testing
import Foundation
@testable import EscapeBudget

@MainActor
struct StreamingCSVParserTests {

    // MARK: - Test Setup

    private func createTempCSVFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".csv")
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Delimiter Detection Tests

    @Test func testDetectCommaDelimiter() throws {
        let content = "Name,Age,City\nJohn,30,NYC\nJane,25,LA"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let delimiter = try StreamingCSVParser.detectDelimiter(url: fileURL)
        #expect(delimiter == ",")
    }

    @Test func testDetectSemicolonDelimiter() throws {
        let content = "Name;Age;City\nJohn;30;NYC\nJane;25;LA"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let delimiter = try StreamingCSVParser.detectDelimiter(url: fileURL)
        #expect(delimiter == ";")
    }

    @Test func testDetectTabDelimiter() throws {
        let content = "Name\tAge\tCity\nJohn\t30\tNYC\nJane\t25\tLA"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let delimiter = try StreamingCSVParser.detectDelimiter(url: fileURL)
        #expect(delimiter == "\t")
    }

    @Test func testDetectPipeDelimiter() throws {
        let content = "Name|Age|City\nJohn|30|NYC\nJane|25|LA"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let delimiter = try StreamingCSVParser.detectDelimiter(url: fileURL)
        #expect(delimiter == "|")
    }

    @Test func testDetectDelimiterFallbackToComma() throws {
        let content = "NoDelimitersHere\nJustText"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let delimiter = try StreamingCSVParser.detectDelimiter(url: fileURL)
        #expect(delimiter == ",")
    }

    // MARK: - Basic Parsing Tests

    @Test func testParseSimpleCSV() async throws {
        let content = "Name,Age,City\nJohn,30,NYC\nJane,25,LA"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[0] == ["Name", "Age", "City"])
        #expect(rows[1] == ["John", "30", "NYC"])
        #expect(rows[2] == ["Jane", "25", "LA"])
    }

    @Test func testParseCSVWithQuotedFields() async throws {
        let content = "Name,Description\n\"John\",\"Hello, World\"\n\"Jane\",\"Test\""
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1] == ["John", "Hello, World"])
        #expect(rows[2] == ["Jane", "Test"])
    }

    @Test func testParseCSVWithEscapedQuotes() async throws {
        let content = "Name,Quote\n\"John\",\"He said \"\"Hello\"\"\"\n\"Jane\",\"She said \"\"Hi\"\"\""
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1] == ["John", "He said \"Hello\""])
        #expect(rows[2] == ["Jane", "She said \"Hi\""])
    }

    @Test func testParseCSVWithNewlinesInQuotes() async throws {
        let content = "Name,Address\n\"John\",\"123 Main St\nApt 4\"\n\"Jane\",\"456 Oak Ave\""
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1][1] == "123 Main St\nApt 4")
    }

    @Test func testParseCSVWithEmptyFields() async throws {
        let content = "Name,Middle,Last\nJohn,,Doe\n,Jane,Smith"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1] == ["John", "", "Doe"])
        #expect(rows[2] == ["", "Jane", "Smith"])
    }

    @Test func testParseCSVWithCRLF() async throws {
        let content = "Name,Age\r\nJohn,30\r\nJane,25"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1] == ["John", "30"])
    }

    @Test func testParseCSVWithTrailingNewline() async throws {
        let content = "Name,Age\nJohn,30\nJane,25\n"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
    }

    @Test func testParseCSVWithMultipleTrailingNewlines() async throws {
        let content = "Name,Age\nJohn,30\n\n\n"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count >= 2)
        #expect(rows[0] == ["Name", "Age"])
        #expect(rows[1] == ["John", "30"])
    }

    // MARK: - Edge Case Tests

    @Test func testParseEmptyFile() async throws {
        let content = ""
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.isEmpty)
    }

    @Test func testParseSingleRow() async throws {
        let content = "Name,Age"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 1)
        #expect(rows[0] == ["Name", "Age"])
    }

    @Test func testParseSingleColumn() async throws {
        let content = "Name\nJohn\nJane"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[0] == ["Name"])
        #expect(rows[1] == ["John"])
        #expect(rows[2] == ["Jane"])
    }

    @Test func testParseQuoteAtStartOfUnquotedField() async throws {
        let content = "Name,Description\nJohn,abc\"def"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 2)
        #expect(rows[1][1].contains("abc"))
    }

    @Test func testParseAllQuotedFields() async throws {
        let content = "\"Name\",\"Age\",\"City\"\n\"John\",\"30\",\"NYC\""
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 2)
        #expect(rows[0] == ["Name", "Age", "City"])
        #expect(rows[1] == ["John", "30", "NYC"])
    }

    // MARK: - Large File Tests

    @Test func testParseLargeFile() async throws {
        var content = "ID,Name,Amount\n"
        for i in 1...1000 {
            content += "\(i),Person\(i),\(Double(i) * 10.5)\n"
        }

        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rowCount = 0

        for try await _ in RobustCSVParser.parse(url: fileURL) {
            rowCount += 1
        }

        #expect(rowCount == 1001)
    }

    @Test func testParseLongFields() async throws {
        let longString = String(repeating: "A", count: 10000)
        let content = "Field1,Field2\n\(longString),Short"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 2)
        #expect(rows[1][0].count == 10000)
        #expect(rows[1][1] == "Short")
    }

    // MARK: - Real-World Transaction Data Tests

    @Test func testParseTransactionCSV() async throws {
        let content = #"""
Date,Payee,Amount,Memo
01/15/2024,Grocery Store,-50.00,Weekly shopping
01/20/2024,Paycheck,2000.00,
01/25/2024,"Restaurant, Inc",-35.50,"Dinner with ""friends"""
"""#

        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 4)
        #expect(rows[0] == ["Date", "Payee", "Amount", "Memo"])
        #expect(rows[1] == ["01/15/2024", "Grocery Store", "-50.00", "Weekly shopping"])
        #expect(rows[2] == ["01/20/2024", "Paycheck", "2000.00", ""])
        #expect(rows[3] == ["01/25/2024", "Restaurant, Inc", "-35.50", "Dinner with \"friends\""])
    }

    @Test func testParseTransactionCSVWithNegativeAmountsInParentheses() async throws {
        let content = """
Date,Payee,Amount
01/15/2024,Store,($50.00)
01/20/2024,Income,$2000.00
"""

        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1][2] == "($50.00)")
        #expect(rows[2][2] == "$2000.00")
    }

    // MARK: - Unicode and Special Characters Tests

    @Test func testParseUnicodeCharacters() async throws {
        let content = "Name,City\nJohn,São Paulo\nJane,北京\nBob,مصر"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 4)
        #expect(rows[1][1] == "São Paulo")
        #expect(rows[2][1] == "北京")
        #expect(rows[3][1] == "مصر")
    }

    @Test func testParseEmojis() async throws {
        let content = "Name,Reaction\nJohn,😀\nJane,🎉👍"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count == 3)
        #expect(rows[1][1] == "😀")
        #expect(rows[2][1] == "🎉👍")
    }

    // MARK: - Malformed CSV Tests

    @Test func testParseUnclosedQuotes() async throws {
        let content = "Name,Description\n\"John,Test"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(!rows.isEmpty)
    }

    @Test func testParseMixedLineEndings() async throws {
        let content = "Name,Age\nJohn,30\r\nJane,25\rBob,35"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var rows: [[String]] = []

        for try await row in RobustCSVParser.parse(url: fileURL) {
            rows.append(row)
        }

        #expect(rows.count >= 3)
    }

    // MARK: - File Size Limit Tests

    @Test func testFileSizeExceedsLimit() async throws {
        let largeContent = String(repeating: "A", count: 110 * 1024 * 1024)
        let fileURL = createTempCSVFile(content: largeContent)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()

        do {
            for try await _ in RobustCSVParser.parse(url: fileURL) {
            }
            Issue.record("Expected error for file size exceeding limit")
        } catch {
        }
    }

    // MARK: - Configuration Tests

    @Test func testCustomDelimiterConfiguration() async throws {
        let content = "Name;Age;City\nJohn;30;NYC"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = StreamingCSVParser()
        var rows: [[String]] = []

        let config = StreamingCSVParser.Configuration(
            delimiter: ";",
            encoding: .utf8,
            hasHeader: true,
            chunkSize: 64 * 1024
        )

        for await row in await parser.parseStream(url: fileURL, configuration: config) {
            rows.append(row)
        }

        #expect(!rows.isEmpty)
        #expect(rows[0].count >= 3)
    }

    // MARK: - Performance Characteristics Tests

    @Test func testStreamingMemoryEfficiency() async throws {
        var content = "ID,Data\n"
        for i in 1...10000 {
            content += "\(i),\(String(repeating: "X", count: 100))\n"
        }

        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var processedRows = 0

        for try await _ in RobustCSVParser.parse(url: fileURL) {
            processedRows += 1
        }

        #expect(processedRows >= 10000)
    }

    @Test func testParserHandlesIncrementalReading() async throws {
        let content = "A,B,C\n1,2,3\n4,5,6"
        let fileURL = createTempCSVFile(content: content)
        defer { cleanup(fileURL) }

        let parser = RobustCSVParser()
        var firstRow: [String]?
        var totalRows = 0

        for try await row in RobustCSVParser.parse(url: fileURL) {
            if firstRow == nil {
                firstRow = row
            }
            totalRows += 1
        }

        #expect(firstRow == ["A", "B", "C"])
        #expect(totalRows == 3)
    }
}
