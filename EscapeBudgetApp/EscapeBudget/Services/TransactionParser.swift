//
//  TransactionParser.swift
//  EscapeBudget
//
//  Created by Admin on 12/13/25.
//

import Foundation
import PDFKit

struct ParsedFile {
    var rows: [[String]]
    var fileName: String
}

// MARK: - Compatibility Adapter
// Preserved for ImportView.swift or other legacy usages
final class TransactionParser {
    typealias ProgressHandler = ([[String]]) async -> Bool
    
    func parse(url: URL, onRowsProgress: ProgressHandler? = nil) async throws -> ParsedFile {
        var rows: [[String]] = []
        var count = 0
        
        // Use the robust parser from StreamingCSVParser.swift
        for try await row in RobustCSVParser.parse(url: url) {
            rows.append(row)
            count += 1
            
            // Report progress every 500 rows
            if let handler = onRowsProgress, count % 500 == 0 {
                let shouldContinue = await handler(rows)
                if !shouldContinue { break }
            }
        }
        
        // Final progress report
        if let handler = onRowsProgress {
            _ = await handler(rows)
        }
        
        return ParsedFile(rows: rows, fileName: url.lastPathComponent)
    }
}
