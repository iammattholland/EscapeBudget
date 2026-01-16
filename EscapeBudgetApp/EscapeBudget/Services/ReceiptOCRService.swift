import Foundation
import Vision
import UIKit

/// Service for extracting text and data from receipt images using Vision OCR
@MainActor
struct ReceiptOCRService {

    struct ParsedReceipt {
        var merchant: String?
        var date: Date?
        var total: Decimal?
        var items: [ReceiptItem]
        var rawText: String
    }

    /// Extract text from an image using Vision OCR
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw ReceiptError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ReceiptError.ocrFailed)
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Parse receipt data from extracted text
    static func parseReceipt(from text: String) -> ParsedReceipt {
        let lines = text.split(separator: "\n").map(String.init)

        var merchant: String?
        var date: Date?
        var total: Decimal?
        var items: [ReceiptItem] = []

        // Extract merchant (usually first 1-2 lines)
        if let firstLine = lines.first, !firstLine.isEmpty {
            merchant = firstLine.trimmingCharacters(in: .whitespaces)
        }

        // Extract date
        date = extractDate(from: lines)

        // Extract total
        total = extractTotal(from: lines)

        // Extract line items
        items = extractLineItems(from: lines)

        return ParsedReceipt(
            merchant: merchant,
            date: date,
            total: total,
            items: items,
            rawText: text
        )
    }

    // MARK: - Private Helpers

    private static func extractDate(from lines: [String]) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Try various date formats
        let formats = [
            "MM/dd/yyyy",
            "MM/dd/yy",
            "M/d/yyyy",
            "M/d/yy",
            "yyyy-MM-dd",
            "MMM dd, yyyy",
            "dd MMM yyyy"
        ]

        for line in lines {
            for format in formats {
                dateFormatter.dateFormat = format

                // Try to find date pattern in line
                let components = line.components(separatedBy: .whitespaces)
                for component in components {
                    if let date = dateFormatter.date(from: component) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private static func extractTotal(from lines: [String]) -> Decimal? {
        // Look for "Total", "TOTAL", "Amount", etc.
        let totalKeywords = ["total", "amount", "balance", "due"]

        for (index, line) in lines.enumerated() {
            let lowercaseLine = line.lowercased()

            // Check if line contains a total keyword
            if totalKeywords.contains(where: { lowercaseLine.contains($0) }) {
                // Look for amount in this line or next line
                if let amount = extractAmount(from: line) {
                    return amount
                }

                // Check next line
                if index + 1 < lines.count, let amount = extractAmount(from: lines[index + 1]) {
                    return amount
                }
            }
        }

        // Fallback: find largest amount (likely the total)
        let amounts = lines.compactMap { extractAmount(from: $0) }
        return amounts.max()
    }

    private static func extractLineItems(from lines: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []

        for line in lines {
            // Skip if line seems like header/footer
            let lower = line.lowercased()
            if lower.contains("total") || lower.contains("tax") ||
               lower.contains("subtotal") || lower.isEmpty {
                continue
            }

            // Try to extract price from line
            if let price = extractAmount(from: line) {
                // Extract item name (everything before the price)
                let itemName = extractItemName(from: line, price: price)

                if !itemName.isEmpty && price > 0 {
                    items.append(ReceiptItem(
                        name: itemName,
                        price: price,
                        quantity: 1
                    ))
                }
            }
        }

        return items
    }

    private static func extractAmount(from text: String) -> Decimal? {
        // Match patterns like: $12.34, 12.34, $12
        let pattern = "\\$?([0-9]+[.,][0-9]{2})"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        if let matchRange = Range(match.range(at: 1), in: text) {
            var amountString = String(text[matchRange])
            // Replace comma with period if needed
            amountString = amountString.replacingOccurrences(of: ",", with: ".")
            return Decimal(string: amountString)
        }

        return nil
    }

    private static func extractItemName(from line: String, price: Decimal) -> String {
        // Remove the price from the line to get item name
        let priceString = String(format: "%.2f", NSDecimalNumber(decimal: price).doubleValue)
        var name = line
            .replacingOccurrences(of: "$\(priceString)", with: "")
            .replacingOccurrences(of: priceString, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading quantity indicators (1x, 2x, etc.)
        name = name.replacingOccurrences(of: "^[0-9]+[xX]?\\s*", with: "", options: .regularExpression)

        return name
    }
}

// MARK: - Errors

enum ReceiptError: LocalizedError {
    case invalidImage
    case ocrFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .ocrFailed:
            return "Failed to extract text from receipt"
        case .compressionFailed:
            return "Failed to compress image"
        }
    }
}

// MARK: - Image Compression

extension UIImage {
    /// Compress image to target size (max 100 KB for thumbnails)
    func compressedData(maxSizeKB: Int = 100) -> Data? {
        let maxBytes = maxSizeKB * 1024
        var compression: CGFloat = 0.8

        guard var imageData = self.jpegData(compressionQuality: compression) else {
            return nil
        }

        // Reduce compression until under target size
        while imageData.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            guard let compressedData = self.jpegData(compressionQuality: compression) else {
                break
            }
            imageData = compressedData
        }

        // If still too large, resize image
        if imageData.count > maxBytes {
            let ratio = sqrt(CGFloat(maxBytes) / CGFloat(imageData.count))
            let newSize = CGSize(
                width: size.width * ratio,
                height: size.height * ratio
            )

            if let resizedImage = resize(to: newSize) {
                imageData = resizedImage.jpegData(compressionQuality: 0.8) ?? imageData
            }
        }

        return imageData
    }

    private func resize(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
