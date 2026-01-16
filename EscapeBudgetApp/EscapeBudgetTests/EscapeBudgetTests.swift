import Testing
import Foundation
import SwiftUI
@testable import EscapeBudget

struct EscapeBudgetTests {

    // MARK: - Date Format Parsing Tests
    
    @Test func testDateFormatMMDDYYYY() throws {
        let format = DateFormatOption.mmddyyyy
        let result = format.parse("12/25/2024")
        #expect(result != nil)
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: result!)
        #expect(components.month == 12)
        #expect(components.day == 25)
        #expect(components.year == 2024)
    }
    
    @Test func testDateFormatDDMMYYYY() throws {
        let format = DateFormatOption.ddmmyyyy
        let result = format.parse("25/12/2024")
        #expect(result != nil)
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: result!)
        #expect(components.month == 12)
        #expect(components.day == 25)
        #expect(components.year == 2024)
    }
    
    @Test func testDateFormatYYYYMMDD() throws {
        let format = DateFormatOption.yyyymmdd
        let result = format.parse("2024-12-25")
        #expect(result != nil)
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: result!)
        #expect(components.month == 12)
        #expect(components.day == 25)
        #expect(components.year == 2024)
    }
    
    @Test func testDateFormatInvalid() throws {
        let format = DateFormatOption.mmddyyyy
        let result = format.parse("not-a-date")
        #expect(result == nil)
    }
    
    @Test func testDateFormatWithWhitespace() throws {
        let format = DateFormatOption.mmddyyyy
        let result = format.parse("  12/25/2024  ")
        #expect(result != nil)
    }
    
    // MARK: - ImportedTransaction Tests
    
    @Test func testImportedTransactionCreation() throws {
        let date = Date()
        let transaction = ImportedTransaction(
            date: date,
            payee: "Test Payee",
            amount: Decimal(-50.00),
            memo: "Test memo"
        )
        
        #expect(transaction.payee == "Test Payee")
        #expect(transaction.amount == Decimal(-50.00))
        #expect(transaction.memo == "Test memo")
        #expect(transaction.isSelected == true)
        #expect(transaction.isDuplicate == false)
    }
    
    @Test func testImportedTransactionSelection() throws {
        var transaction = ImportedTransaction(
            date: Date(),
            payee: "Test",
            amount: Decimal(100)
        )
        
        #expect(transaction.isSelected == true)
        
        transaction.isSelected = false
        #expect(transaction.isSelected == false)
    }
    
    // MARK: - ColumnType Tests
    
    @Test func testColumnTypeIdentifiable() throws {
        for type in ColumnType.allCases {
            #expect(!type.id.isEmpty)
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test func testColumnTypeColors() throws {
        // Verify each column type has a distinct color
        #expect(ColumnType.date.color != ColumnType.skip.color)
        #expect(ColumnType.payee.color != ColumnType.skip.color)
        #expect(ColumnType.amount.color != ColumnType.skip.color)
    }
    
    // MARK: - Amount Parsing Simulation Tests
    
    @Test func testAmountParsingWithDollarSign() throws {
        let input = "$1,234.56"
        let clean = input
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let result = Decimal(string: clean)
        #expect(result == Decimal(string: "1234.56"))
    }
    
    @Test func testAmountParsingNegativeParentheses() throws {
        let input = "($500.00)"
        var clean = input
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
        let result = Decimal(string: clean)
        #expect(result == Decimal(string: "-500.00"))
    }
    
    @Test func testAmountParsingEmpty() throws {
        let input = ""
        let result = input.isEmpty ? Decimal.zero : (Decimal(string: input) ?? Decimal.zero)
        #expect(result == Decimal.zero)
    }
    
    // MARK: - AccountType Tests
    
    @Test func testAccountTypeProperties() throws {
        // Verify all AccountType cases have valid icons and colors configured
        // This ensures no compile/runtime errors when new types are added
        for type in AccountType.allCases {
            #expect(!type.icon.isEmpty, "Icon should not be empty for \(type.rawValue)")
            
            // Just accessing the color property to ensure it's defined
            let _ = type.color
        }
    }
}
