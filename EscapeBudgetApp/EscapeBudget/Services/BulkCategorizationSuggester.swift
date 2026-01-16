import Foundation
import SwiftData

/// Groups similar transactions and suggests categories based on historical patterns
@MainActor
struct BulkCategorizationSuggester {
    let modelContext: ModelContext

    /// Represents a group of similar transactions with a suggested category
    struct SuggestionGroup: Identifiable {
        let id = UUID()
        let normalizedPayee: String
        let transactions: [Transaction]
        let suggestedCategory: Category?
        let confidence: Double // 0.0 to 1.0
        let isTransferLikely: Bool // Detected transfer keywords in payee
        let reason: String?

        var totalAmount: Decimal {
            transactions.reduce(0) { $0 + abs($1.amount) }
        }

        var displayPayee: String {
            // Use the most common payee variation
            let payeeCounts = Dictionary(grouping: transactions, by: { $0.payee })
                .mapValues { $0.count }
            return payeeCounts.max(by: { $0.value < $1.value })?.key ?? normalizedPayee
        }
    }

    /// Generate categorization suggestions for uncategorized transactions
    func generateSuggestions(for transactions: [Transaction]) -> [SuggestionGroup] {
        // Filter to only standard uncategorized transactions
        let uncategorized = transactions.filter {
            $0.kind == .standard && $0.category == nil
        }

        guard !uncategorized.isEmpty else { return [] }

        let enabledRules = fetchEnabledRules()
        let (patternsByPayee, allPatternKeys) = fetchPatternsIndex()
        let allCategories = fetchAllCategories()

        // Group by normalized payee
        let grouped = Dictionary(grouping: uncategorized) { transaction in
            PayeeNormalizer.normalizeForComparison(transaction.payee)
        }

        // Generate suggestions for each group
        var suggestions: [SuggestionGroup] = []

        for (normalizedPayee, groupTransactions) in grouped {
            // Check if this looks like a transfer based on payee name
            let isTransferLikely = detectTransferKeywords(in: normalizedPayee)

            let (category, confidence, reason) = suggestCategory(
                for: normalizedPayee,
                transactions: groupTransactions,
                isTransferLikely: isTransferLikely,
                enabledRules: enabledRules,
                patternsByPayee: patternsByPayee,
                allPatternKeys: allPatternKeys,
                allCategories: allCategories
            )

            // Only include groups with suggestions or significant transaction count
            if category != nil || groupTransactions.count >= 3 || isTransferLikely {
                suggestions.append(SuggestionGroup(
                    normalizedPayee: normalizedPayee,
                    transactions: groupTransactions,
                    suggestedCategory: category,
                    confidence: confidence,
                    isTransferLikely: isTransferLikely,
                    reason: reason
                ))
            }
        }

        // Sort by confidence (high to low), then by transaction count (high to low)
        return suggestions.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.transactions.count > rhs.transactions.count
        }
    }

    /// Suggest a category for a normalized payee based on historical patterns
    private func suggestCategory(
        for normalizedPayee: String,
        transactions: [Transaction],
        isTransferLikely: Bool,
        enabledRules: [AutoRule],
        patternsByPayee: [String: [CategoryPattern]],
        allPatternKeys: [String],
        allCategories: [Category]
    ) -> (Category?, Double, String?) {
        // Don't suggest categories for likely transfers
        if isTransferLikely {
            return (nil, 0.0, "looks like a transfer")
        }

        // Strategy 1: Exact matching auto rules (user-defined)
        if let (category, matchShare) = checkAutoRules(rules: enabledRules, transactions: transactions) {
            let confidence = min(0.98, max(0.80, 0.70 + (matchShare * 0.30)))
            return (category, confidence, "matches an auto rule")
        }

        // Strategy 2: Learned patterns for this payee (fast, user-history based)
        if let (category, confidence, reason) = checkLearnedPatterns(
            normalizedPayee: normalizedPayee,
            patternsByPayee: patternsByPayee,
            allPatternKeys: allPatternKeys
        ) {
            return (category, confidence, reason)
        }

        // Strategy 3: Payee name keyword analysis (fallback, not user-specific)
        if let keywordCategory = checkPayeeKeywords(normalizedPayee: normalizedPayee, allCategories: allCategories) {
            return (keywordCategory, 0.65, "payee keywords")
        }

        // Strategy 4: Amount-based heuristics
        if let amountCategory = checkAmountHeuristics(transactions: transactions, allCategories: allCategories) {
            return (amountCategory, 0.55, "amount pattern")
        }

        return (nil, 0.0, nil)
    }

    /// Detect if payee name suggests it's a transfer
    private func detectTransferKeywords(in payee: String) -> Bool {
        let transferKeywords = [
            "transfer", "xfer", "tfr", "e-transfer", "etransfer",
            "payment to", "payment from", "sent to", "received from",
            "interac", "zelle", "venmo", "paypal transfer",
            "move money", "account transfer", "internal transfer",
            "withdrawal to", "deposit from",
            "cc payment", "credit card payment", "card payment",
            "visa payment", "mastercard payment", "amex payment",
            "bill payment", "pmt"
        ]

        let lowercased = payee.lowercased()
        return transferKeywords.contains { lowercased.contains($0) }
    }

    /// Analyze payee name for category hints
    private func checkPayeeKeywords(normalizedPayee: String, allCategories: [Category]) -> Category? {
        let expenseCategories = allCategories.filter { $0.group?.type == .expense }
        let lowercased = normalizedPayee.lowercased()

        // Dining & Food keywords
        let diningKeywords = ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "burger", "pizza", "sushi", "taco", "diner", "bistro", "grill", "kitchen", "eatery", "bar", "pub", "brewery", "winery", "bakery", "donut", "sandwich", "deli"]
        if diningKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("dining") || name.contains("restaurant") || name.contains("food") || name.contains("eating")
            }
        }

        // Groceries keywords
        let groceryKeywords = ["grocery", "supermarket", "market", "trader joe", "whole foods", "safeway", "kroger", "walmart", "target", "costco", "fresh", "organic", "produce"]
        if groceryKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("grocer") || name.contains("food")
            }
        }

        // Gas & Fuel keywords
        let gasKeywords = ["gas", "fuel", "shell", "chevron", "exxon", "mobil", "bp", "arco", "petro", "station"]
        if gasKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("gas") || name.contains("fuel") || name.contains("auto") || name.contains("transport")
            }
        }

        // Utilities keywords
        let utilityKeywords = ["electric", "power", "water", "gas company", "utility", "pge", "edison", "energy", "internet", "cable", "phone", "wireless", "verizon", "att", "t-mobile", "comcast", "spectrum"]
        if utilityKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("utilit") || name.contains("bill") || name.contains("internet") || name.contains("phone")
            }
        }

        // Healthcare keywords
        let healthKeywords = ["pharmacy", "doctor", "dental", "medical", "health", "hospital", "clinic", "cvs", "walgreen", "rite aid", "urgent care", "lab", "imaging"]
        if healthKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("health") || name.contains("medical") || name.contains("pharmacy")
            }
        }

        // Entertainment keywords
        let entertainmentKeywords = ["movie", "cinema", "theater", "theatre", "netflix", "spotify", "hulu", "disney", "streaming", "game", "xbox", "playstation", "entertainment", "concert", "ticket"]
        if entertainmentKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("entertainment") || name.contains("recreation") || name.contains("streaming")
            }
        }

        // Shopping keywords
        let shoppingKeywords = ["amazon", "shop", "store", "retail", "mall", "outlet", "boutique", "apparel", "clothing"]
        if shoppingKeywords.contains(where: { lowercased.contains($0) }) {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("shopping") || name.contains("retail") || name.contains("clothing")
            }
        }

        let incomeCategories = allCategories.filter { $0.group?.type == .income }

        let salaryKeywords = ["payroll", "salary", "paycheck", "pay cheque", "wages", "direct deposit"]
        if salaryKeywords.contains(where: { lowercased.contains($0) }) {
            return incomeCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("salary") || name.contains("pay") || name.contains("income")
            } ?? incomeCategories.first
        }

        let refundKeywords = ["interest", "dividend", "cashback", "cash back", "rebate", "refund"]
        if refundKeywords.contains(where: { lowercased.contains($0) }) {
            let refundExpense = expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("refund") || name.contains("rebate") || name.contains("cash back")
            }
            if let refundExpense { return refundExpense }
            return incomeCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("other") || name.contains("misc") || name.contains("income")
            } ?? incomeCategories.first
        }

        return nil
    }

    private func fetchEnabledRules() -> [AutoRule] {
        let descriptor = FetchDescriptor<AutoRule>(
            predicate: #Predicate<AutoRule> { $0.isEnabled },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchPatternsIndex() -> ([String: [CategoryPattern]], [String]) {
        let descriptor = FetchDescriptor<CategoryPattern>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        let allPatterns = (try? modelContext.fetch(descriptor)) ?? []
        let byPayee = Dictionary(grouping: allPatterns) { $0.payeePattern }
        return (byPayee, Array(byPayee.keys))
    }

    private func fetchAllCategories() -> [Category] {
        (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
    }

    /// Check if any enabled AutoRule matches a meaningful share of this group.
    private func checkAutoRules(rules: [AutoRule], transactions: [Transaction]) -> (Category, Double)? {
        guard !rules.isEmpty else { return nil }

        var best: (category: Category, share: Double, matched: Int, order: Int)?

        for (index, rule) in rules.enumerated() {
            guard let category = rule.actionCategory else { continue }
            guard category.group?.type != .transfer else { continue }

            var matched = 0
            for tx in transactions {
                if rule.matches(payee: tx.payee, account: tx.account, amount: tx.amount) {
                    matched += 1
                }
            }

            guard matched > 0 else { continue }
            let share = Double(matched) / Double(transactions.count)
            guard share >= 0.60 else { continue }

            let candidate = (category: category, share: share, matched: matched, order: index)
            if let current = best {
                if candidate.share > current.share { best = candidate }
                else if candidate.share == current.share, candidate.matched > current.matched { best = candidate }
                else if candidate.share == current.share, candidate.matched == current.matched, candidate.order < current.order { best = candidate }
            } else {
                best = candidate
            }
        }

        guard let best else { return nil }
        return (best.category, best.share)
    }

    private func checkLearnedPatterns(
        normalizedPayee: String,
        patternsByPayee: [String: [CategoryPattern]],
        allPatternKeys: [String]
    ) -> (Category, Double, String)? {
        func bestFromPatterns(_ patterns: [CategoryPattern], scale: Double, reason: String) -> (Category, Double, String)? {
            let candidates: [(pattern: CategoryPattern, category: Category)] = patterns.compactMap { pattern in
                guard let category = pattern.category else { return nil }
                guard category.group?.type != .transfer else { return nil }
                return (pattern, category)
            }
            guard !candidates.isEmpty else { return nil }

            let best = candidates.max { lhs, rhs in
                if lhs.pattern.confidence != rhs.pattern.confidence { return lhs.pattern.confidence < rhs.pattern.confidence }
                if lhs.pattern.successfulMatches != rhs.pattern.successfulMatches { return lhs.pattern.successfulMatches < rhs.pattern.successfulMatches }
                return lhs.pattern.lastUsedAt < rhs.pattern.lastUsedAt
            }

            guard let best else { return nil }
            return (best.category, min(0.95, best.pattern.confidence * scale), reason)
        }

        if let patterns = patternsByPayee[normalizedPayee],
           let exact = bestFromPatterns(patterns, scale: 1.0, reason: "learned from your past categorizations") {
            return exact
        }

        // Fuzzy: any pattern where payee contains/is contained (helps store numbers/variants).
        guard normalizedPayee.count >= 4 else { return nil }
        var bestFuzzy: (Category, Double, String)?

        for key in allPatternKeys where key.count >= 4 {
            if normalizedPayee.contains(key) || key.contains(normalizedPayee) {
                if let patterns = patternsByPayee[key],
                   let candidate = bestFromPatterns(patterns, scale: 0.85, reason: "similar to a learned payee pattern") {
                    if let current = bestFuzzy {
                        if candidate.1 > current.1 { bestFuzzy = candidate }
                    } else {
                        bestFuzzy = candidate
                    }
                }
            }
        }

        return bestFuzzy
    }

    /// Suggest category based on amount patterns
    private func checkAmountHeuristics(transactions: [Transaction], allCategories: [Category]) -> Category? {
        let avgAmount = transactions.map { abs($0.amount) }.reduce(0, +) / Decimal(transactions.count)

        let expenseCategories = allCategories.filter {
            $0.group?.type == .expense
        }

        // Small amounts (< $20) - likely dining, coffee, or entertainment
        if avgAmount < 20 {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("dining") || name.contains("food") ||
                       name.contains("coffee") || name.contains("restaurant")
            }
        }

        // Medium amounts ($100-$300) - likely shopping or groceries
        if avgAmount >= 100 && avgAmount < 300 {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("shopping") || name.contains("groceries") ||
                       name.contains("retail")
            }
        }

        // Large regular amounts (> $500) - likely bills or utilities
        if avgAmount >= 500 {
            return expenseCategories.first { category in
                let name = category.name.lowercased()
                return name.contains("utilities") || name.contains("bills") ||
                       name.contains("rent") || name.contains("mortgage")
            }
        }

        return nil
    }

    /// Apply a category to all transactions in a suggestion group
    func applySuggestion(group: SuggestionGroup, category: Category, selectedTransactionIDs: Set<PersistentIdentifier>) throws {
        let autoRulesService = AutoRulesService(modelContext: modelContext)

        for transaction in group.transactions where selectedTransactionIDs.contains(transaction.persistentModelID) {
            let old = TransactionSnapshot(from: transaction)
            TransactionStatsUpdateCoordinator.markDirty(transactionSnapshot: old)
            transaction.category = category
            TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)

            // Log the categorization
            let reason = group.reason.map { " • \($0)" } ?? ""
            TransactionHistoryService.append(
                detail: "Smart categorized to \(category.name) (confidence: \(Int(group.confidence * 100))%)\(reason).",
                to: transaction,
                in: modelContext
            )

            if transaction.kind == .standard, transaction.category != nil {
                autoRulesService.learnFromCategorization(transaction: transaction, wasAutoDetected: true)
            }
        }

        try modelContext.save()
        DataChangeTracker.bump()
    }
}
