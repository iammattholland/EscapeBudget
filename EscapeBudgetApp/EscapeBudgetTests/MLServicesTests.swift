import Testing
import Foundation
import SwiftData
@testable import EscapeBudget

/// Comprehensive tests for ML-based services
@MainActor
struct MLServicesTests {

    // MARK: - CategoryPredictor Tests

    @Test("CategoryPredictor: Predicts category based on learned patterns")
    func testCategoryPredictorBasicPrediction() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            CategoryPattern.self,
            BudgetForecast.self,
            configurations: config
        )
        let context = container.mainContext

        // Create test category
        let category = Category(name: "Groceries", assigned: 500)
        context.insert(category)

        // Create a learned pattern
        let pattern = CategoryPattern(category: category, payeePattern: "walmart")
        pattern.useCount = 10
        pattern.successfulMatches = 10
        pattern.rejectedMatches = 0
        context.insert(pattern)

        try context.save()

        // Create predictor and test transaction
        let predictor = CategoryPredictor(modelContext: context)
        let transaction = Transaction(
            date: Date(),
            payee: "WALMART SUPERCENTER",
            amount: -45.67
        )

        // Predict category
        let prediction = predictor.predictCategory(for: transaction)

        #expect(prediction != nil)
        #expect(prediction?.category.name == "Groceries")
        #expect(prediction?.confidence ?? 0 > 0.5)
    }

    @Test("CategoryPredictor: Returns nil for unknown payee")
    func testCategoryPredictorNoMatch() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            CategoryPattern.self,
            BudgetForecast.self,
            configurations: config
        )
        let context = container.mainContext

        let predictor = CategoryPredictor(modelContext: context)
        let transaction = Transaction(
            date: Date(),
            payee: "UNKNOWN MERCHANT 12345",
            amount: -99.99
        )

        let prediction = predictor.predictCategory(for: transaction)
        #expect(prediction == nil)
    }

    // MARK: - DuplicateDetectorML Tests

    @Test("DuplicateDetectorML: Detects exact duplicates")
    func testDuplicateDetectorExactMatch() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Chequing", type: .chequing, balance: 1000)
        context.insert(account)

        let date = Date()
        let original = Transaction(
            date: date,
            payee: "Coffee Shop",
            amount: -4.50,
            account: account
        )
        context.insert(original)

        let duplicate = Transaction(
            date: date,
            payee: "Coffee Shop",
            amount: -4.50,
            account: account
        )
        context.insert(duplicate)

        try context.save()

        let detector = DuplicateDetectorML(modelContext: context)
        let candidates = detector.findDuplicates(for: duplicate)

        #expect(candidates.count > 0)
        #expect(candidates.first?.matchType == .exact)
        #expect(candidates.first?.similarity ?? 0 > 0.9)
    }

    @Test("DuplicateDetectorML: Detects similar transactions")
    func testDuplicateDetectorSimilarMatch() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Chequing", type: .chequing, balance: 1000)
        context.insert(account)

        let date = Date()
        let original = Transaction(
            date: date,
            payee: "Starbucks #1234",
            amount: -5.75,
            account: account
        )
        context.insert(original)

        let similar = Transaction(
            date: date.addingTimeInterval(3600), // 1 hour later
            payee: "Starbucks #5678",
            amount: -5.75,
            account: account
        )
        context.insert(similar)

        try context.save()

        let detector = DuplicateDetectorML(modelContext: context)
        let candidates = detector.findDuplicates(for: similar)

        #expect(candidates.count > 0)
        #expect(candidates.first?.similarity ?? 0 > 0.7)
    }

    // MARK: - RecurringDetectorML Tests

    @Test("RecurringDetectorML: Detects monthly recurring pattern")
    func testRecurringDetectorMonthlyPattern() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            RecurringPattern.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Chequing", type: .chequing, balance: 1000)
        context.insert(account)

        // Create monthly recurring transactions
        let calendar = Calendar.current
        for month in 0..<6 {
            guard let date = calendar.date(byAdding: .month, value: -month, to: Date()) else { continue }
            let transaction = Transaction(
                date: date,
                payee: "Netflix Subscription",
                amount: -15.99,
                account: account
            )
            context.insert(transaction)
        }

        try context.save()

        let detector = RecurringDetectorML(modelContext: context)
        let patterns = await detector.detectRecurringPatterns()

        #expect(patterns.count > 0)
        let netflixPattern = patterns.first { $0.payeePattern.contains("netflix") }
        #expect(netflixPattern != nil)
        #expect(netflixPattern?.frequency == .monthly)
    }

    @Test("RecurringDetectorML: Checks for recurring match")
    func testRecurringDetectorMatchCheck() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            CategoryGroup.self,
            Category.self,
            RecurringPattern.self,
            configurations: config
        )
        let context = container.mainContext

        // Create a recurring pattern
        let pattern = RecurringPattern(payee: "spotify", frequency: .monthly)
        pattern.typicalAmount = 9.99
        pattern.minAmount = 9.99
        pattern.maxAmount = 9.99
        pattern.occurrenceCount = 5
        pattern.confidence = 0.85
        context.insert(pattern)

        try context.save()

        let detector = RecurringDetectorML(modelContext: context)
        let transaction = Transaction(
            date: Date(),
            payee: "Spotify Premium",
            amount: -9.99
        )

        let suggestion = detector.checkForRecurringMatch(transaction)

        #expect(suggestion != nil)
        #expect(suggestion?.pattern.payeePattern == "spotify")
        #expect(suggestion?.confidence ?? 0 > 0.5)
    }

    // MARK: - PayeeNormalizerML Tests

    @Test("PayeeNormalizerML: Normalizes payee name")
    func testPayeeNormalizerNormalization() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CategoryGroup.self,
            Category.self,
            PayeePattern.self,
            configurations: config
        )
        let context = container.mainContext

        // Create a payee pattern
        let pattern = PayeePattern(canonicalName: "Target", variant: "TARGET #1234")
        pattern.addVariant("TARGET STORE")
        pattern.confidence = 0.9
        pattern.useCount = 10
        context.insert(pattern)

        try context.save()

        let normalizer = PayeeNormalizerML(modelContext: context)
        let result = normalizer.normalize("TARGET #5678")

        #expect(result != nil)
        #expect(result?.canonicalName == "Target")
    }

    @Test("PayeeNormalizerML: Suggests similar payees")
    func testPayeeNormalizerSuggestions() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CategoryGroup.self,
            Category.self,
            PayeePattern.self,
            configurations: config
        )
        let context = container.mainContext

        let pattern = PayeePattern(canonicalName: "McDonald's", variant: "MCDONALDS")
        pattern.addVariant("MCD")
        context.insert(pattern)

        try context.save()

        let normalizer = PayeeNormalizerML(modelContext: context)
        let suggestions = normalizer.getSuggestions(for: "MCDONLDS")  // Typo

        #expect(suggestions.count > 0)
        #expect(suggestions.first?.pattern.canonicalName == "McDonald's")
    }

    // MARK: - BudgetForecaster Tests

    @Test("BudgetForecaster: Forecasts category spending")
    func testBudgetForecasterForecast() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            BudgetForecast.self,
            configurations: config
        )
        let context = container.mainContext

        let category = Category(name: "Dining", assigned: 300)
        context.insert(category)

        // Create historical spending data
        let calendar = Calendar.current
        for month in 0..<6 {
            guard let date = calendar.date(byAdding: .month, value: -month, to: Date()) else { continue }

            // Add 10 transactions per month
            for _ in 0..<10 {
                let transaction = Transaction(
                    date: date,
                    payee: "Restaurant",
                    amount: Decimal(-Double.random(in: 20...50)),
                    category: category
                )
                context.insert(transaction)
            }
        }

        try context.save()

        let forecaster = BudgetForecaster(modelContext: context)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let forecast = await forecaster.forecastCategory(category, for: nextMonth)

        #expect(forecast != nil)
        #expect(forecast?.predictedAmount ?? 0 > 0)
        #expect(forecast?.confidence ?? 0 > 0)
    }

    @Test("BudgetForecaster: Returns nil for insufficient data")
    func testBudgetForecasterInsufficientData() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Account.self,
            CategoryGroup.self,
            Category.self,
            BudgetForecast.self,
            configurations: config
        )
        let context = container.mainContext

        let category = Category(name: "New Category", assigned: 100)
        context.insert(category)

        // Only 1 transaction - not enough for forecast
        let transaction = Transaction(
            date: Date(),
            payee: "Test",
            amount: -50,
            category: category
        )
        context.insert(transaction)

        try context.save()

        let forecaster = BudgetForecaster(modelContext: context)
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let forecast = await forecaster.forecastCategory(category, for: nextMonth)

        #expect(forecast == nil)
    }
}
