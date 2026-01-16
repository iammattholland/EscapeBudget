import Foundation
import SwiftData

/// ML-based budget forecasting service
@MainActor
final class BudgetForecaster {
    private let modelContext: ModelContext

    struct ForecastResult {
        let category: Category?
        let monthYear: Date
        let predictedAmount: Decimal
        let confidence: Double
        let trend: BudgetForecast.TrendDirection
        let suggestedBudget: Decimal?
        let reasoning: String
    }

    struct Config {
        var lookbackMonths: Int = 6
        var minMonthsForForecast: Int = 3
        var trendSensitivity: Double = 0.1  // 10% change to detect trend

        nonisolated init(lookbackMonths: Int = 6, minMonthsForForecast: Int = 3, trendSensitivity: Double = 0.1) {
            self.lookbackMonths = lookbackMonths
            self.minMonthsForForecast = minMonthsForForecast
            self.trendSensitivity = trendSensitivity
        }
    }

    private let config: Config

    init(modelContext: ModelContext, config: Config = Config()) {
        self.modelContext = modelContext
        self.config = config
    }

    /// Generate forecast for next month across all categories
    func generateMonthlyForecasts(for monthYear: Date? = nil) async -> [ForecastResult] {
        let targetMonth = monthYear ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

        // Fetch all categories
        let categoryDescriptor = FetchDescriptor<Category>()
        guard let categories = try? modelContext.fetch(categoryDescriptor) else { return [] }

        var forecasts: [ForecastResult] = []

        for category in categories {
            if let forecast = await forecastCategory(category, for: targetMonth) {
                forecasts.append(forecast)

                // Save forecast to database
                let forecastModel = BudgetForecast(
                    category: category,
                    monthYear: targetMonth,
                    predictedSpending: forecast.predictedAmount,
                    confidence: forecast.confidence,
                    basedOnMonths: config.lookbackMonths,
                    trend: forecast.trend
                )
                forecastModel.suggestedBudget = forecast.suggestedBudget

                modelContext.insert(forecastModel)

                // Yield periodically
                if forecasts.count % 5 == 0 {
                    await Task.yield()
                }
            }
        }

        _ = modelContext.safeSave(
            context: "BudgetForecaster.generateForecasts",
            showErrorToUser: false
        )

        return forecasts
    }

    /// Forecast spending for a specific category
    func forecastCategory(_ category: Category, for monthYear: Date) async -> ForecastResult? {
        let historicalData = await getHistoricalSpending(category: category)
        guard historicalData.count >= config.minMonthsForForecast else { return nil }

        // Calculate statistics
        let amounts = historicalData.map { $0.amount }
        let average = amounts.reduce(Decimal(0), +) / Decimal(amounts.count)
        _ = amounts.min() ?? 0  // minAmount
        _ = amounts.max() ?? 0  // maxAmount

        // Detect trend
        let trend = detectTrend(historicalData)

        // Apply trend to prediction
        let prediction: Decimal
        let confidence: Double

        switch trend {
        case .increasing:
            // Predict 10% increase
            prediction = average * Decimal(1.10)
            confidence = 0.7
        case .decreasing:
            // Predict 10% decrease
            prediction = average * Decimal(0.90)
            confidence = 0.7
        case .stable:
            // Use average
            prediction = average
            confidence = 0.8
        }

        // Suggest budget with buffer
        let suggestedBudget = prediction * Decimal(1.15)  // 15% buffer

        // Generate reasoning
        let reasoning = generateReasoning(
            historical: amounts,
            trend: trend,
            prediction: prediction
        )

        return ForecastResult(
            category: category,
            monthYear: monthYear,
            predictedAmount: prediction,
            confidence: confidence,
            trend: trend,
            suggestedBudget: suggestedBudget,
            reasoning: reasoning
        )
    }

    /// Compare forecast accuracy against actual spending
    func evaluateForecastAccuracy(month: Date) -> [(category: Category, variance: Double, forecast: BudgetForecast)] {
        // Fetch forecasts for this month
        let descriptor = FetchDescriptor<BudgetForecast>(
            predicate: #Predicate { $0.monthYear == month }
        )

        guard let forecasts = try? modelContext.fetch(descriptor) else { return [] }

        var results: [(Category, Double, BudgetForecast)] = []

        for forecast in forecasts {
            guard let category = forecast.category else { continue }

            // Get actual spending for this month
            let actualSpending = getActualSpending(category: category, month: month)

            let variance = forecast.calculateVariance(actual: actualSpending)
            results.append((category, variance, forecast))
        }

        return results.sorted { $0.1 < $1.1 }  // Sort by accuracy
    }

    // MARK: - Private Methods

    private func getHistoricalSpending(category: Category) async -> [(month: Date, amount: Decimal)] {
        let startDate = Calendar.current.date(byAdding: .month, value: -config.lookbackMonths, to: Date()) ?? Date()
        let categoryID = category.persistentModelID

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.date >= startDate
            },
            sortBy: [SortDescriptor(\.date)]
        )

        guard let allTransactions = try? modelContext.fetch(descriptor) else { return [] }
        let transactions = allTransactions.filter {
            $0.kind == .standard && $0.category?.persistentModelID == categoryID
        }

        // Group by month
        var monthlySpending: [Date: Decimal] = [:]
        let calendar = Calendar.current

        for tx in transactions {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            monthlySpending[month, default: 0] += abs(tx.amount)
        }

        return monthlySpending.map { ($0.key, $0.value) }.sorted { $0.month < $1.month }
    }

    private func getActualSpending(category: Category, month: Date) -> Decimal {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            return 0
        }

        let categoryID = category.persistentModelID
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { tx in
                tx.date >= startOfMonth &&
                tx.date <= endOfMonth
            }
        )

        guard let allTransactions = try? modelContext.fetch(descriptor) else { return 0 }
        let transactions = allTransactions.filter {
            $0.kind == .standard && $0.category?.persistentModelID == categoryID
        }

        return transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    private func detectTrend(_ data: [(month: Date, amount: Decimal)]) -> BudgetForecast.TrendDirection {
        guard data.count >= 2 else { return .stable }

        // Simple linear regression approach
        let firstHalf = data.prefix(data.count / 2)
        let secondHalf = data.suffix(data.count / 2)

        let firstAvg = firstHalf.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(firstHalf.count)
        let secondAvg = secondHalf.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(secondHalf.count)

        guard firstAvg > 0 else { return .stable }

        let changePercent = NSDecimalNumber(decimal: (secondAvg - firstAvg) / firstAvg).doubleValue

        if changePercent > config.trendSensitivity {
            return .increasing
        } else if changePercent < -config.trendSensitivity {
            return .decreasing
        } else {
            return .stable
        }
    }

    private func generateReasoning(
        historical: [Decimal],
        trend: BudgetForecast.TrendDirection,
        prediction: Decimal
    ) -> String {
        let avg = historical.reduce(Decimal(0), +) / Decimal(historical.count)
        let avgDouble = NSDecimalNumber(decimal: avg).doubleValue
        let predDouble = NSDecimalNumber(decimal: prediction).doubleValue

        var parts: [String] = []

        parts.append("Based on \(historical.count) months of history")

        switch trend {
        case .increasing:
            parts.append("spending is trending up")
        case .decreasing:
            parts.append("spending is trending down")
        case .stable:
            parts.append("spending is relatively stable")
        }

        if predDouble > avgDouble * 1.1 {
            parts.append("predicting higher than average")
        } else if predDouble < avgDouble * 0.9 {
            parts.append("predicting lower than average")
        }

        return parts.joined(separator: ", ")
    }
}
