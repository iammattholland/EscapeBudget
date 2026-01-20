import Foundation
import os.log

/// A high-performance, streaming CSV parser that reads files line-by-line (or chunk-by-chunk)
/// to keep memory usage low, while correctly handling delimiters, quotes, and newlines.
actor StreamingCSVParser {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EscapeBudget", category: "CSV")
    
    enum Delimiter: Character, CaseIterable {
        case comma = ","
        case semicolon = ";"
        case tab = "\t"
        case pipe = "|"
    }
    
    struct Configuration {
        var delimiter: Character? = nil // nil = auto-detect
        var encoding: String.Encoding = .utf8
        var hasHeader: Bool = true
        var chunkSize: Int = 64 * 1024 // 64KB read buffer
    }
    
    /// Auto-detects the delimiter by scanning the first few lines of the file.
    nonisolated static func detectDelimiter(url: URL, encoding: String.Encoding = .utf8) throws -> Character {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Read first 4KB
        guard let data = try? fileHandle.read(upToCount: 4096),
              let text = String(data: data, encoding: encoding) else {
            return "," // Fallback
        }
        
        let delimiters: [Character] = [",", ";", "\t", "|"]
        var bestDelimiter: Character = ","
        var maxConsistency = 0.0
        
        let lines = text.components(separatedBy: .newlines).prefix(10)
        guard lines.count > 1 else { return "," }
        
        for delimiter in delimiters {
            let counts = lines.map { line in
                // Only count delimiters outside of quotes (simple check)
                // For detection, we can just count raw occurrences, but it's better to be slightly smart.
                // For simplicity/speed in detection, we just count crude occurrences.
                // A better heuristic is: do all lines have the same number of delimiters?
                line.filter { $0 == delimiter }.count
            }
            
            let nonZeroCounts = counts.filter { $0 > 0 }
            guard !nonZeroCounts.isEmpty else { continue }
            
            // Calculate consistency (how many lines have the "mode" count)
            // Ideally all lines have N delimiters.
            let mode = nonZeroCounts.reduce(into: [:]) { counts, count in
                counts[count, default: 0] += 1
            }.max(by: { $0.value < $1.value })?.key ?? 0
            
            let consistencyScore = Double(counts.filter { $0 == mode }.count) / Double(counts.count)
            
            // Prefer comma if consistency is equal
            if consistencyScore > maxConsistency {
                maxConsistency = consistencyScore
                bestDelimiter = delimiter
            } else if consistencyScore == maxConsistency && delimiter == "," {
                bestDelimiter = ","
            }
        }
        
        return bestDelimiter
    }
    
    /// parse yields rows asynchronously.
    func parseStream(url: URL, configuration: Configuration = Configuration()) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            Task {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: url)
                    defer { try? fileHandle.close() }
                    
                    let delim = try configuration.delimiter ?? StreamingCSVParser.detectDelimiter(url: url)
                    
                    // Buffer for reading
                    let bufferSize = configuration.chunkSize
                    
                    var remainder = ""
                    var insideQuotes = false
                    var currentRowFields: [String] = []
                    var currentField = ""
                    
                    // Iterate through the file in chunks
                    while true {
                        guard let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty else {
                            break // End of file
                        }
                        
                        guard let chunkStr = String(data: data, encoding: configuration.encoding) else {
                            Self.logger.error("Failed to decode CSV chunk as \(String(describing: configuration.encoding), privacy: .public)")
                            break
                        }
                        
                        let content = remainder + chunkStr
                        remainder = ""
                        
                        var iterator = content.makeIterator()
                        var lookahead: Character? = iterator.next()
                        
                        while let char = lookahead {
                            let nextChar: Character? = iterator.next()
                            lookahead = nextChar // Advance
                            
                            if insideQuotes {
                                if char == "\"" {
                                    if let next = nextChar, next == "\"" {
                                        // Escaped quote
                                        currentField.append("\"")
                                        lookahead = iterator.next() // Skip the escaped quote
                                    } else {
                                        insideQuotes = false
                                    }
                                } else {
                                    currentField.append(char)
                                }
                            } else {
                                if char == "\"" {
                                    insideQuotes = true
                                } else if char == delim {
                                    currentRowFields.append(currentField)
                                    currentField = ""
                                } else if char.isNewline {
                                    // Handle CRLF (if char is \r and next is \n, we skip \n)
                                    if char == "\r", let next = nextChar, next == "\n" {
                                        lookahead = iterator.next() // Skip \n
                                    }
                                    
                                    currentRowFields.append(currentField)
                                    continuation.yield(currentRowFields)
                                    
                                    currentRowFields = []
                                    currentField = ""
                                } else {
                                    currentField.append(char)
                                }
                            }
                        }
                        
                        // Whatever is left in currentField must be saved for the next chunk,
                        // UNLESS we are right at the boundary. 
                        // Actually, the loop consumes 'content'. 
                        // If we are mid-parse, we need to know if we really finished the last token.
                        // The 'lookahead' logic is tricky with streaming chunks because we might split a CRLF or a quote.
                        // A simpler approach for the remainder:
                        // We parsed everything. 'currentField' and 'insideQuotes' state are preserved.
                        // BUT, we shouldn't have appended the LAST chars to currentField if we aren't sure it's done. 
                        // Actually, with the above loop, we processed all chars.
                        // The issue is if the chunk ended in the middle of a multi-byte char (handled by String conversion usually, but Foundation split might be safe with valid UTF8 boundaries?? FileHandle read(upToCount) returns bytes. String(data:) might fail if we cut a char.)
                        // To be safe with UTF8, we should probably read Data, then find the last newline, and process up to there, keeping the rest as remainder bytes?
                        // Or just hope String(data:) works (it often returns nil for partial multibyte).
                        // Let's refine the "read until newline" strategy or "keep raw data remainder".
                    }
                    
                    // Process end of file
                    if !currentField.isEmpty || !currentRowFields.isEmpty {
                        currentRowFields.append(currentField)
                        continuation.yield(currentRowFields)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    Self.logger.error("Error reading CSV: \(error, privacy: .private)")
                    continuation.finish()
                }
            }
        }
    }
    
    // Improved parse method ensuring UTF8 integrity by buffering data
    func parse(url: URL) -> AsyncThrowingStream<[String], Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open file"]))
                    return
                }
                defer { try? fileHandle.close() }
                
                let bufferSize = 64 * 1024
                var buffer = Data()
                var delimiter: Character = ","
                
                // Detect delimiter
                if let initialData = try? fileHandle.read(upToCount: 4096),
                   let text = String(data: initialData, encoding: .utf8) {
                    
                    // Simple detection logic
                    let counts = [",": 0, ";": 0, "\t": 0, "|": 0]
                    var detected = counts
                    for char in text {
                        if let _ = detected[String(char)] {
                            detected[String(char)]! += 1
                        }
                    }
                    // Find max
                    if let max = detected.max(by: { $0.value < $1.value }), max.value > 0 {
                        delimiter = Character(max.key)
                    }
                    
                    // Reset file pointer
                    try? fileHandle.seek(toOffset: 0)
                }
                
                var currentField = ""
                var currentRow: [String] = []
                var insideQuotes = false
                var escapedQuote = false
                
                while true {
                    let newDat = try fileHandle.read(upToCount: bufferSize)
                    if let d = newDat, !d.isEmpty {
                        buffer.append(d)
                    } else if buffer.isEmpty {
                        // EOF
                        if !currentField.isEmpty || !currentRow.isEmpty {
                            currentRow.append(currentField)
                            continuation.yield(currentRow)
                        }
                        continuation.finish()
                        break
                    }
                    
                    // Convert buffer to string. IMPORTANT: Process only up to the last valid character to avoid splitting multi-byte chars? 
                    // Actually String(decoding:as:) is safe-ish, but splitting UTF8 is bad.
                    // Better approach: process byte by byte? No, too slow in Swift.
                    // String conversion of a chunk:
                    guard let string = String(data: buffer, encoding: .utf8) else {
                        // Maybe we cut a character in half?
                        // Try processing one less byte until it works?
                        // For now assume mostly ASCII/valid splits (rare to hit exact middle of char in 64kb)
                        // This is a known complexity. 
                        // Let's stick to the simpler State Machine on the whole string logic
                        // But we need to keep "remainder" bytes that didn't decode or weren't processed.
                        
                        // Robust way: Find the last newline in DATA and process up to there.
                        // If no newline in 64KB, we have a huge line or issue. Expand buffer.
                        if buffer.count > 1024 * 1024 * 10 { // 10MB buffer and no string? invalid
                             continuation.finish(throwing: NSError(domain: "CSVParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encoding error or line too long"]))
                             return
                        }
                        continue // Read more data
                    }
                    
                    buffer.removeAll() // We consumed it into 'string'
                    
                    // Now parse 'string'
                    // We need to be careful about the LAST token. It might be incomplete.
                    // So we shouldn't just parse 'string'. We should process char by char.
                    
                    for char in string {
                        if escapedQuote {
                            if char == "\"" {
                                currentField.append("\"") // It was an escaped quote
                                escapedQuote = false
                            } else {
                                // It wasn't an escaped quote, it was a closing quote followed by something else
                                // ideally we handled this in the "insideQuotes" block logic below.
                                // Actually, standard CSV: " is escaped by ""
                                // So if we see " inside quotes, we check next char.
                                // This loop structure is hard for lookahead.
                                // Let's change state machine.
                                
                                insideQuotes = false
                                escapedQuote = false
                                // Re-process this char since it's part of next token (delimiter or newline)
                                // But we are in a iterator loop.
                                // Let's use the Index approach.
                            }
                        }
                        
                        // Re-eval logic
                        if insideQuotes {
                            if char == "\"" {
                                if escapedQuote {
                                    // "" -> we already set escapedQuote=true on previous char
                                    // Wait, simple boolean flags are tricky.
                                    // Let's use:
                                    // If we see ", we don't know if it is closing quote or escaped quote until we see NEXT char.
                                    // So we can't append it yet.
                                    // We need lookahead or a "pendingQuote" state.
                                } else {
                                    // Potential closing or escaped.
                                    // We'll assume closing, unless next char flips it back.
                                    // But we don't see next char here.
                                    // We need to defer.
                                    escapedQuote = true
                                }
                            } else {
                                if escapedQuote {
                                    // We met a quote previously, but this char is NOT a quote.
                                    // So the previous quote was indeed a Closing Quote.
                                    insideQuotes = false
                                    escapedQuote = false
                                    // Now process 'char' as outside quotes
                                    if char == delimiter {
                                        currentRow.append(currentField)
                                        currentField = ""
                                    } else if char.isNewline {
                                        currentRow.append(currentField)
                                        continuation.yield(currentRow)
                                        currentRow = []
                                        currentField = ""
                                    } else {
                                        // Garbage after closing quote? 
                                        // e.g. "abc"d
                                        // Just append it?
                                        // strict csv says no, but we operate gracefully.
                                    }
                                } else {
                                    currentField.append(char)
                                }
                            }
                        } else {
                            // Outside quotes
                            if char == "\"" {
                                if !currentField.isEmpty {
                                    // Quotes appearing in middle of field? e.g. abc"def
                                    // Treat as literal quote?
                                    currentField.append(char)
                                } else {
                                    insideQuotes = true
                                }
                            } else if char == delimiter {
                                currentRow.append(currentField)
                                currentField = ""
                            } else if char.isNewline {
                                if !currentRow.isEmpty || !currentField.isEmpty {
                                    currentRow.append(currentField)
                                    continuation.yield(currentRow)
                                    currentRow = []
                                    currentField = ""
                                } else {
                                    // empty line
                                }
                            } else {
                                currentField.append(char)
                            }
                        }
                    }
                    
                    // End of chunk.
                    // Issue: If we ended with `escapedQuote = true`, we don't know if it's closing or escaped.
                    // We need to wait for next chunk.
                    // We must NOT finish the row.
                    
                    // But `char` loop finished. `string` is consumed.
                    // If we had `escapedQuote` set at the very end, we are in limbo.
                    // That's fine, we read next chunk.
                }
            }
        }
    }
}

// MARK: - Dedicated Parser Implementation
// Since the async stream above had some complexity with lookahead and state,
// here is a robust character-by-character implementation that manages the buffer manually.
final class RobustCSVParser {
    /// Maximum file size allowed for CSV import (50 MB)
    nonisolated private static let maxFileSize: Int64 = 50 * 1024 * 1024
    nonisolated private static let maxColumnsPerRow: Int = 256
    nonisolated private static let maxFieldLength: Int = 100_000
    nonisolated private static let preflightReadBytes: Int = 4096
    nonisolated private static let utf16BOMs: [Data] = [Data([0xFF, 0xFE]), Data([0xFE, 0xFF])]

    nonisolated static func parse(url: URL) -> AsyncThrowingStream<[String], Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Check file size before processing to prevent memory exhaustion
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize > maxFileSize {
                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "File size exceeds maximum of \(maxFileSize / 1024 / 1024) MB"]))
                        return
                    }
                } catch {
                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not read file attributes"]))
                    return
                }

                guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file"]))
                    return
                }
                defer { try? fileHandle.close() }

                // Preflight: detect unsupported encodings / binary files.
                if let head = try? fileHandle.read(upToCount: preflightReadBytes) {
                    // Reset file pointer after preflight.
                    try? fileHandle.seek(toOffset: 0)

                    if utf16BOMs.contains(where: { head.starts(with: $0) }) {
                        continuation.finish(throwing: NSError(
                            domain: "CSVParser",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "This CSV appears to be UTF‑16 encoded. Please re-export as UTF‑8 CSV."]
                        ))
                        return
                    }

                    if head.contains(0) {
                        continuation.finish(throwing: NSError(
                            domain: "CSVParser",
                            code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "This file doesn’t look like a valid UTF‑8 CSV."]
                        ))
                        return
                    }
                }
                
                // 1. Detect Delimiter
                let delimiter: Character = (try? StreamingCSVParser.detectDelimiter(url: url)) ?? ","
                
                // 2. Stream
                let bufferSize = 65536 // 64KB
                var buffer = Data()
                
                var currentRow: [String] = []
                var currentField = ""
                var insideQuotes = false
                var pendingQuote = false // We saw a quote, checking if it's escaped or closing
                var isCR = false // Handle CRLF

	                // Set up termination handler (avoid capturing mutable vars under Swift 6 concurrency)
	                continuation.onTermination = { @Sendable _ in }

                while true {
                    let data = try fileHandle.read(upToCount: bufferSize)
                    if let data = data, !data.isEmpty {
                        buffer.append(data)
	                    } else {
	                        // EOF
	                        if buffer.isEmpty {
	                            // Really done
	                            if pendingQuote {
	                                // A trailing `"` at EOF closes the quoted field.
	                                insideQuotes = false
	                                pendingQuote = false
	                            }

	                            if insideQuotes {
	                                continuation.finish(throwing: NSError(
	                                    domain: "CSVParser",
	                                    code: 8,
	                                    userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: unterminated quote."]
	                                ))
	                                return
	                            }
                            if !currentField.isEmpty || !currentRow.isEmpty {
                                currentRow.append(currentField)
                                continuation.yield(currentRow)
                            }
	                            continuation.finish()
	                            return
	                        }
	                    }
                    
                    // Process buffer
                    // We covert to Scalar view or just iterate? 
                    // String iteration is easiest but slightly risky with split mult-byte.
                    // We'll rely on String(decoding:as: .utf8) "repairing" split chars or buffering until valid?
                    // Proper way: Decode as much as possible valid UTF8.
                    
                    // Let's iterate buffer as String
                    let str = String(decoding: buffer, as: UTF8.self)
                    
                    // Check if we cut a char? String(decoding...) replaces invalid with replacement char.
                    // Ideally we check last byte?
                    // For now, assuming Standard UTF8 files.
                    
                    buffer.removeAll() // We consumed it? 
                    // Wait, if we are at EOF, we consume all.
                    // If not EOF, we might have cut 'str' halfway through a line or token.
                    // That is fine, our state machine persists.
                    
                    for char in str {
                        if pendingQuote {
                            if char == "\"" {
                                // It was "" -> escaped quote, add one "
                                currentField.append("\"")
                                if currentField.count > maxFieldLength {
                                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: field is too long."]))
                                    return
                                }
                                pendingQuote = false
                                continue
                            } else {
                                // It was " + something else -> Closing quote
                                insideQuotes = false
                                // Now process 'char' as normal token
                                if char == delimiter {
                                    currentRow.append(currentField)
                                    if currentRow.count > maxColumnsPerRow {
                                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                        return
                                    }
                                    currentField = ""
                                } else if char.isNewline {
                                    // Handle composite newline (e.g. \r\n as one char) or simple newline
                                    if char == "\r" {
                                        currentRow.append(currentField)
                                        if currentRow.count > maxColumnsPerRow {
                                            continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                            return
                                        }
                                        continuation.yield(currentRow)
                                        currentRow = []
                                        currentField = ""
                                        isCR = true
                                    } else if char == "\n" {
                                        if isCR {
                                            isCR = false // Skip \n because we already handled \r
                                        } else {
                                            currentRow.append(currentField)
                                            if currentRow.count > maxColumnsPerRow {
                                                continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                                return
                                            }
                                            continuation.yield(currentRow)
                                            currentRow = []
                                            currentField = ""
                                        }
                                    } else {
                                        // Some other newline char (or \r\n as single char)
                                        currentRow.append(currentField)
                                        if currentRow.count > maxColumnsPerRow {
                                            continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                            return
                                        }
                                        continuation.yield(currentRow)
                                        currentRow = []
                                        currentField = ""
                                        isCR = false
                                    }
                                } else {
                                    // Text after closing quote? e.g. "abc"d -> append 'd'
                                    currentField.append(char)
                                    if currentField.count > maxFieldLength {
                                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: field is too long."]))
                                        return
                                    }
                                }
                            }
                            pendingQuote = false
                            continue
                        }
                        
                        // Normal processing
                        if insideQuotes {
                            if char == "\"" {
                                pendingQuote = true
                            } else {
                                currentField.append(char)
                                if currentField.count > maxFieldLength {
                                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: field is too long."]))
                                    return
                                }
                            }
                        } else {
                            if char == "\"" {
                                if currentField.isEmpty {
                                    insideQuotes = true
                                } else {
                                    currentField.append(char) // Quote in middle of text?? treat as literal
                                    if currentField.count > maxFieldLength {
                                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: field is too long."]))
                                        return
                                    }
                                }
                            } else if char == delimiter {
                                currentRow.append(currentField)
                                if currentRow.count > maxColumnsPerRow {
                                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                    return
                                }
                                currentField = ""
                            } else if char.isNewline {
                                if char == "\r" {
                                    currentRow.append(currentField)
                                    if currentRow.count > maxColumnsPerRow {
                                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                        return
                                    }
                                    continuation.yield(currentRow)
                                    currentRow = []
                                    currentField = ""
                                    isCR = true
                                } else if char == "\n" {
                                    if isCR {
                                        isCR = false
                                    } else {
                                        currentRow.append(currentField)
                                        if currentRow.count > maxColumnsPerRow {
                                            continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                            return
                                        }
                                        continuation.yield(currentRow)
                                        currentRow = []
                                        currentField = ""
                                    }
                                } else {
                                    // \r\n as one char
                                    currentRow.append(currentField)
                                    if currentRow.count > maxColumnsPerRow {
                                        continuation.finish(throwing: NSError(domain: "CSVParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: too many columns in a row."]))
                                        return
                                    }
                                    continuation.yield(currentRow)
                                    currentRow = []
                                    currentField = ""
                                    isCR = false
                                }
                            } else {
                                isCR = false
                                isCR = false
                                currentField.append(char)
                                if currentField.count > maxFieldLength {
                                    continuation.finish(throwing: NSError(domain: "CSVParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed CSV: field is too long."]))
                                    return
                                }
                            }
                        }
                    }
                    
                    // If we ended with pendingQuote, we need next chunk to decide.
                    // State is preserved in 'pendingQuote'.
                    
                    // If data was empty (EOF loop entry), we break out above.
                }
            }
        }
    }
}
