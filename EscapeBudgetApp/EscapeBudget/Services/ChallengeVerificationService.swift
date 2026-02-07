import Foundation
import SwiftData

/// Service to verify spending challenge completion based on transaction data
@MainActor
struct ChallengeVerificationService {

    /// Verifies the current status of a challenge and updates progress
    /// Returns updated progress (0.0 to 1.0) and whether challenge passed/failed
    static func verify(
        challenge: SpendingChallenge,
        transactions: [Transaction],
        categories: [Category],
        monthlyBudgets: [MonthlyCategoryBudget] = []
    ) -> ChallengeResult {
        switch challenge.type {
        case .noSpendDay:
            return verifyNoSpendDay(challenge: challenge, transactions: transactions)
        case .noSpendWeekend:
            return verifyNoSpendWeekend(challenge: challenge, transactions: transactions)
        case .coffeeShopFast:
            return verifyCategoryAvoidance(challenge: challenge, transactions: transactions, keywords: challenge.type.relevantCategoryKeywords)
        case .restaurantReduction:
            return verifyRestaurantReduction(challenge: challenge, transactions: transactions)
        case .groceryBudgetHero:
            return verifyGroceryBudget(challenge: challenge, transactions: transactions, categories: categories, monthlyBudgets: monthlyBudgets)
        case .underBudgetStreak:
            return verifyUnderBudgetStreak(challenge: challenge, transactions: transactions, categories: categories, monthlyBudgets: monthlyBudgets)
        case .packLunchWeek:
            return verifyPackLunchWeek(challenge: challenge, transactions: transactions)
        case .entertainmentDiet:
            return verifyEntertainmentDiet(challenge: challenge, transactions: transactions)
        case .categoryFreeze:
            return verifyCategoryFreeze(challenge: challenge, transactions: transactions)
        case .weeklySpendingLimit:
            return verifyWeeklySpendingLimit(challenge: challenge, transactions: transactions)
        case .savingsStreak:
            return verifySavingsStreak(challenge: challenge, transactions: transactions)
        case .noImpulseBuys:
            return verifyNoImpulseBuys(challenge: challenge, transactions: transactions)
        case .custom:
            return verifyCustomChallenge(challenge: challenge, transactions: transactions, categories: categories)
        }
    }

    // MARK: - Custom Challenge Verification

    private static func verifyCustomChallenge(
        challenge: SpendingChallenge,
        transactions: [Transaction],
        categories: [Category]
    ) -> ChallengeResult {
        guard let filterType = challenge.customFilterType,
              let targetAmount = challenge.targetAmount else {
            return ChallengeResult(progress: 0.0, passed: false, message: "Invalid challenge configuration")
        }

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let filterValue = challenge.customFilterValue ?? ""

        let matchingSpending: Decimal
        switch filterType {
        case .category:
            matchingSpending = periodTx
                .filter { $0.category?.name.lowercased() == filterValue.lowercased() && $0.amount < 0 }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }

        case .categoryGroup:
            let groupName = challenge.customCategoryGroupName ?? filterValue
            matchingSpending = periodTx
                .filter { $0.category?.group?.name.lowercased() == groupName.lowercased() && $0.amount < 0 }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }

        case .payee:
            matchingSpending = periodTx
                .filter { $0.payee.lowercased().contains(filterValue.lowercased()) && $0.amount < 0 }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }

        case .totalSpending:
            matchingSpending = periodTx
                .filter { isDiscretionaryExpense($0) }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }
        }

        let progress = 1.0 - min(1.0, Double(truncating: matchingSpending as NSNumber) / Double(truncating: targetAmount as NSNumber))
        let isPast = Date() > challenge.endDate
        let passed = matchingSpending <= targetAmount

        return ChallengeResult(
            progress: max(0, progress),
            passed: isPast && passed,
            message: "\(matchingSpending.formatted(.currency(code: "USD"))) of \(targetAmount.formatted(.currency(code: "USD")))"
        )
    }

    // MARK: - Individual Verification Methods

    private static func verifyNoSpendDay(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let dayTransactions = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let discretionarySpending = dayTransactions.filter { isDiscretionaryExpense($0) }

        if discretionarySpending.isEmpty {
            return ChallengeResult(progress: 1.0, passed: true, message: "No spending recorded!")
        } else {
            let total = discretionarySpending.reduce(Decimal.zero) { $0 + abs($1.amount) }
            return ChallengeResult(progress: 0.0, passed: false, message: "Spent \(total.formatted(.currency(code: "USD")))")
        }
    }

    private static func verifyNoSpendWeekend(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let weekendTransactions = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let discretionarySpending = weekendTransactions.filter { isDiscretionaryExpense($0) }

        let calendar = Calendar.current
        let saturday = challenge.startDate
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday

        let saturdayClean = discretionarySpending.filter { calendar.isDate($0.date, inSameDayAs: saturday) }.isEmpty
        let sundayClean = discretionarySpending.filter { calendar.isDate($0.date, inSameDayAs: sunday) }.isEmpty

        let progress = (saturdayClean ? 0.5 : 0) + (sundayClean ? 0.5 : 0)

        if discretionarySpending.isEmpty {
            return ChallengeResult(progress: 1.0, passed: true, message: "Spend-free weekend complete!")
        } else {
            return ChallengeResult(progress: progress, passed: false, message: "\(discretionarySpending.count) transactions found")
        }
    }

    private static func verifyCategoryAvoidance(challenge: SpendingChallenge, transactions: [Transaction], keywords: [String]) -> ChallengeResult {
        let periodTransactions = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let matchingTransactions = periodTransactions.filter { tx in
            let payeeLower = tx.payee.lowercased()
            let categoryLower = tx.category?.name.lowercased() ?? ""
            return keywords.contains { keyword in
                payeeLower.contains(keyword) || categoryLower.contains(keyword)
            }
        }

        let daysElapsed = challenge.daysElapsed
        let totalDays = challenge.totalDays

        if matchingTransactions.isEmpty {
            let progress = min(1.0, Double(daysElapsed) / Double(totalDays))
            let isPast = Date() > challenge.endDate
            return ChallengeResult(
                progress: progress,
                passed: isPast,
                message: isPast ? "Challenge complete!" : "\(challenge.daysRemaining) days to go"
            )
        } else {
            return ChallengeResult(
                progress: 0.0,
                passed: false,
                message: "\(matchingTransactions.count) slip-ups found"
            )
        }
    }

    private static func verifyRestaurantReduction(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let calendar = Calendar.current
        let keywords = challenge.type.relevantCategoryKeywords

        // Current period spending
        let currentPeriodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let currentSpending = sumMatchingTransactions(currentPeriodTx, keywords: keywords)

        // Previous month spending (for comparison)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: challenge.startDate) ?? challenge.startDate
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: challenge.startDate) ?? challenge.startDate
        let previousPeriodTx = filterTransactions(transactions, from: previousStart, to: previousEnd)
        let previousSpending = sumMatchingTransactions(previousPeriodTx, keywords: keywords)

        guard previousSpending > 0 else {
            return ChallengeResult(progress: 1.0, passed: true, message: "No previous spending to compare")
        }

        let targetSpending = previousSpending * Decimal(0.5) // 50% reduction
        let reductionAchieved = 1.0 - (Double(truncating: currentSpending as NSNumber) / Double(truncating: previousSpending as NSNumber))
        let progress = min(1.0, max(0, reductionAchieved * 2)) // Scale to 50% target

        let isPast = Date() > challenge.endDate
        let passed = currentSpending <= targetSpending

        return ChallengeResult(
            progress: progress,
            passed: isPast && passed,
            message: "Down \(Int(reductionAchieved * 100))% vs last month"
        )
    }

    private static func verifyGroceryBudget(challenge: SpendingChallenge, transactions: [Transaction], categories: [Category], monthlyBudgets: [MonthlyCategoryBudget]) -> ChallengeResult {
        let keywords = challenge.type.relevantCategoryKeywords
        let groceryCategory = categories.first { cat in
            keywords.contains { cat.name.lowercased().contains($0) }
        }

        guard let groceryCategory else {
            return ChallengeResult(progress: 0.0, passed: false, message: "No grocery budget set")
        }

        let calculator = CategoryBudgetCalculator(transactions: transactions, monthlyBudgets: monthlyBudgets)
        let budget = max(0, calculator.periodSummary(for: groceryCategory, start: challenge.startDate, end: challenge.endDate).effectiveLimitForPeriod)
        guard budget > 0 else {
            return ChallengeResult(progress: 0.0, passed: false, message: "No grocery budget set")
        }

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let grocerySpending = sumMatchingTransactions(periodTx, keywords: keywords)

        let progress = 1.0 - min(1.0, Double(truncating: grocerySpending as NSNumber) / Double(truncating: budget as NSNumber))
        let isPast = Date() > challenge.endDate
        let passed = grocerySpending <= budget

        return ChallengeResult(
            progress: max(0, progress),
            passed: isPast && passed,
            message: "\(grocerySpending.formatted(.currency(code: "USD"))) of \(budget.formatted(.currency(code: "USD")))"
        )
    }

    private static func verifyUnderBudgetStreak(challenge: SpendingChallenge, transactions: [Transaction], categories: [Category], monthlyBudgets: [MonthlyCategoryBudget]) -> ChallengeResult {
        let calendar = Calendar.current
        let calculator = CategoryBudgetCalculator(transactions: transactions, monthlyBudgets: monthlyBudgets)
        let totalBudget = categories
            .filter { $0.group?.type == .expense }
            .reduce(Decimal.zero) { $0 + max(0, calculator.periodSummary(for: $1, start: challenge.startDate, end: challenge.endDate).effectiveLimitForPeriod) }
        guard totalBudget > 0 else {
            return ChallengeResult(progress: 0.0, passed: false, message: "No budget set")
        }

        let divisor = max(1, challenge.totalDays)
        let dailyBudget = totalBudget / Decimal(divisor)
        var streakDays = 0

        for dayOffset in 0..<challenge.totalDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: challenge.startDate) else { continue }
            if day > Date() { break }

            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? day

            let dayTx = filterTransactions(transactions, from: dayStart, to: dayEnd)
            let daySpending = dayTx.filter { $0.amount < 0 }.reduce(Decimal.zero) { $0 + abs($1.amount) }

            if daySpending <= dailyBudget {
                streakDays += 1
            } else {
                break // Streak broken
            }
        }

        let progress = Double(streakDays) / Double(challenge.totalDays)
        let isPast = Date() > challenge.endDate
        let passed = streakDays >= challenge.totalDays

        return ChallengeResult(
            progress: progress,
            passed: isPast && passed,
            message: "\(streakDays) day streak"
        )
    }

    private static func verifyPackLunchWeek(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let calendar = Calendar.current
        let keywords = ["lunch", "restaurant", "fast food", "takeout", "delivery", "uber eats", "doordash", "grubhub"]

        var cleanWeekdays = 0
        var totalWeekdays = 0

        for dayOffset in 0..<challenge.totalDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: challenge.startDate) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            // Skip weekends (1 = Sunday, 7 = Saturday)
            if weekday == 1 || weekday == 7 { continue }
            if day > Date() { break }

            totalWeekdays += 1

            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? day
            let dayTx = filterTransactions(transactions, from: dayStart, to: dayEnd)

            // Check for lunch-time purchases (10am - 2pm) matching keywords
            let lunchTx = dayTx.filter { tx in
                let hour = calendar.component(.hour, from: tx.date)
                let isLunchTime = hour >= 10 && hour <= 14
                let payeeLower = tx.payee.lowercased()
                let categoryLower = tx.category?.name.lowercased() ?? ""
                let matchesKeywords = keywords.contains { payeeLower.contains($0) || categoryLower.contains($0) }
                return isLunchTime && matchesKeywords && tx.amount < 0
            }

            if lunchTx.isEmpty {
                cleanWeekdays += 1
            }
        }

        let progress = totalWeekdays > 0 ? Double(cleanWeekdays) / Double(max(5, totalWeekdays)) : 0
        let isPast = Date() > challenge.endDate
        let passed = cleanWeekdays >= 5

        return ChallengeResult(
            progress: progress,
            passed: isPast && passed,
            message: "\(cleanWeekdays) of 5 weekdays lunch-free"
        )
    }

    private static func verifyEntertainmentDiet(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let targetAmount = challenge.targetAmount ?? Decimal(100) // Default $100 cap
        let keywords = challenge.type.relevantCategoryKeywords

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let entertainmentSpending = sumMatchingTransactions(periodTx, keywords: keywords)

        let progress = 1.0 - min(1.0, Double(truncating: entertainmentSpending as NSNumber) / Double(truncating: targetAmount as NSNumber))
        let isPast = Date() > challenge.endDate
        let passed = entertainmentSpending <= targetAmount

        return ChallengeResult(
            progress: max(0, progress),
            passed: isPast && passed,
            message: "\(entertainmentSpending.formatted(.currency(code: "USD"))) of \(targetAmount.formatted(.currency(code: "USD"))) cap"
        )
    }

    private static func verifyCategoryFreeze(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        guard let targetCategory = challenge.targetCategoryName else {
            return ChallengeResult(progress: 0.0, passed: false, message: "No category selected")
        }

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let categoryTx = periodTx.filter { $0.category?.name.lowercased() == targetCategory.lowercased() && $0.amount < 0 }

        if categoryTx.isEmpty {
            let progress = min(1.0, Double(challenge.daysElapsed) / Double(challenge.totalDays))
            let isPast = Date() > challenge.endDate
            return ChallengeResult(
                progress: progress,
                passed: isPast,
                message: isPast ? "Category frozen successfully!" : "\(challenge.daysRemaining) days left"
            )
        } else {
            let total = categoryTx.reduce(Decimal.zero) { $0 + abs($1.amount) }
            return ChallengeResult(
                progress: 0.0,
                passed: false,
                message: "\(categoryTx.count) transactions (\(total.formatted(.currency(code: "USD"))))"
            )
        }
    }

    private static func verifyWeeklySpendingLimit(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let targetAmount = challenge.targetAmount ?? Decimal(500) // Default $500/week

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let totalSpending = periodTx.filter { isDiscretionaryExpense($0) }.reduce(Decimal.zero) { $0 + abs($1.amount) }

        let progress = 1.0 - min(1.0, Double(truncating: totalSpending as NSNumber) / Double(truncating: targetAmount as NSNumber))
        let isPast = Date() > challenge.endDate
        let passed = totalSpending <= targetAmount

        return ChallengeResult(
            progress: max(0, progress),
            passed: isPast && passed,
            message: "\(totalSpending.formatted(.currency(code: "USD"))) of \(targetAmount.formatted(.currency(code: "USD"))) limit"
        )
    }

    private static func verifySavingsStreak(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)

        // Look for transfers to savings (positive amounts to savings-related accounts/categories)
        let savingsTransfers = periodTx.filter { tx in
            let isSavingsRelated = tx.category?.name.lowercased().contains("saving") == true ||
                                   tx.account?.name.lowercased().contains("saving") == true ||
                                   tx.payee.lowercased().contains("saving")
            return isSavingsRelated && tx.amount > 0
        }

        let targetCount = max(1, challenge.totalDays / 7) // One transfer per week
        let progress = min(1.0, Double(savingsTransfers.count) / Double(targetCount))
        let isPast = Date() > challenge.endDate
        let passed = savingsTransfers.count >= targetCount

        return ChallengeResult(
            progress: progress,
            passed: isPast && passed,
            message: "\(savingsTransfers.count) of \(targetCount) savings transfers"
        )
    }

    private static func verifyNoImpulseBuys(challenge: SpendingChallenge, transactions: [Transaction]) -> ChallengeResult {
        let threshold = challenge.targetAmount ?? Decimal(50) // Default $50 threshold

        let periodTx = filterTransactions(transactions, from: challenge.startDate, to: challenge.endDate)
        let largePurchases = periodTx.filter { tx in
            abs(tx.amount) >= threshold && tx.amount < 0 && isDiscretionaryExpense(tx)
        }

        // For this challenge, we can't truly verify the 48-hour wait, but we can track large purchases
        // A lower count of large purchases indicates more mindful spending
        let maxExpected = challenge.totalDays / 7 * 2 // Allow ~2 large purchases per week
        let progress = 1.0 - min(1.0, Double(largePurchases.count) / Double(max(1, maxExpected)))

        let isPast = Date() > challenge.endDate

        return ChallengeResult(
            progress: max(0, progress),
            passed: isPast && largePurchases.count <= maxExpected,
            message: "\(largePurchases.count) purchases over \(threshold.formatted(.currency(code: "USD")))"
        )
    }

    // MARK: - Helper Methods

    private static func filterTransactions(_ transactions: [Transaction], from startDate: Date, to endDate: Date) -> [Transaction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate

        return transactions.filter { tx in
            tx.date >= start && tx.date < end && !tx.isTransfer && !tx.isIgnored
        }
    }

    private static func isDiscretionaryExpense(_ transaction: Transaction) -> Bool {
        guard transaction.amount < 0 else { return false }
        guard !transaction.isTransfer && !transaction.isIgnored else { return false }

        // Exclude bills/utilities (non-discretionary)
        let nonDiscretionaryKeywords = ["mortgage", "rent", "insurance", "utility", "electric", "gas bill", "water bill", "tax"]
        let payeeLower = transaction.payee.lowercased()
        let categoryLower = transaction.category?.name.lowercased() ?? ""

        let isNonDiscretionary = nonDiscretionaryKeywords.contains { payeeLower.contains($0) || categoryLower.contains($0) }
        return !isNonDiscretionary
    }

    private static func sumMatchingTransactions(_ transactions: [Transaction], keywords: [String]) -> Decimal {
        transactions
            .filter { tx in
                let payeeLower = tx.payee.lowercased()
                let categoryLower = tx.category?.name.lowercased() ?? ""
                return keywords.contains { payeeLower.contains($0) || categoryLower.contains($0) } && tx.amount < 0
            }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
    }
}

struct ChallengeResult {
    let progress: Double // 0.0 to 1.0
    let passed: Bool
    let message: String
}
