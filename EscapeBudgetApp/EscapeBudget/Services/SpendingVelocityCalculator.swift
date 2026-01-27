import Foundation

/// Represents the spending velocity analysis for a given period
struct SpendingVelocityData {
    // MARK: - Time-based inputs
    let periodStart: Date
    let periodEnd: Date
    let daysInPeriod: Int
    let daysElapsed: Int

    // MARK: - Spending data
    let actualSpent: Decimal
    let budgetAssigned: Decimal

    // MARK: - Computed Velocities

    var daysRemaining: Int {
        max(0, daysInPeriod - daysElapsed)
    }

    /// Average daily spending so far
    var dailyVelocity: Decimal {
        guard daysElapsed > 0 else { return 0 }
        return actualSpent / Decimal(daysElapsed)
    }

    /// Target daily spending to stay within budget
    var targetDailyVelocity: Decimal {
        guard daysInPeriod > 0, budgetAssigned > 0 else { return 0 }
        return budgetAssigned / Decimal(daysInPeriod)
    }

    /// Ratio of actual velocity to target velocity (1.0 = on pace)
    var velocityRatio: Double {
        guard targetDailyVelocity > 0 else { return 1.0 }
        return Double(truncating: (dailyVelocity / targetDailyVelocity) as NSNumber)
    }

    // MARK: - Projections

    /// Projected total spending by end of period at current rate
    var projectedPeriodEndSpent: Decimal {
        dailyVelocity * Decimal(daysInPeriod)
    }

    /// Projected remaining budget (negative if over)
    var projectedRemainingBudget: Decimal {
        budgetAssigned - projectedPeriodEndSpent
    }

    /// How much over budget we're projected to be (0 if under)
    var projectedOverBudget: Decimal {
        max(0, projectedPeriodEndSpent - budgetAssigned)
    }

    // MARK: - Status

    enum Status: String {
        case underPace = "Under Pace"
        case onPace = "On Track"
        case slightlyOver = "Slightly Ahead"
        case overPace = "Over Pace"
        case noBudget = "No Budget Set"
        case noSpending = "No Spending Yet"
    }

    var status: Status {
        guard budgetAssigned > 0 else { return .noBudget }
        guard actualSpent > 0 else { return .noSpending }

        switch velocityRatio {
        case ..<0.85: return .underPace
        case 0.85...1.15: return .onPace
        case 1.15...1.30: return .slightlyOver
        default: return .overPace
        }
    }

    var statusLabel: String {
        status.rawValue
    }

    /// Whether the indicator has meaningful data to display
    var isUsable: Bool {
        daysElapsed > 0 && budgetAssigned > 0
    }

    /// Whether the period has completed
    var isPeriodComplete: Bool {
        daysRemaining == 0
    }

    /// Progress through the period (0.0 to 1.0)
    var periodProgress: Double {
        guard daysInPeriod > 0 else { return 0 }
        return Double(daysElapsed) / Double(daysInPeriod)
    }
}

// MARK: - Calculator

@MainActor
struct SpendingVelocityCalculator {

    /// Computes velocity data from period dates and spending totals
    /// - Parameters:
    ///   - periodStart: Start date of the budget period
    ///   - periodEnd: End date of the budget period
    ///   - referenceDate: The "today" date for calculations (defaults to now)
    ///   - totalSpent: Total expenses in the period
    ///   - budgetAssigned: Total budget assigned for the period
    /// - Returns: SpendingVelocityData with all computed metrics
    static func compute(
        periodStart: Date,
        periodEnd: Date,
        referenceDate: Date = Date(),
        totalSpent: Decimal,
        budgetAssigned: Decimal
    ) -> SpendingVelocityData {
        let calendar = Calendar.current

        // Calculate days in period
        let periodComponents = calendar.dateComponents([.day], from: periodStart, to: periodEnd)
        let daysInPeriod = max(1, (periodComponents.day ?? 0) + 1)

        // Calculate days elapsed (clamped to period bounds)
        let effectiveToday = min(referenceDate, periodEnd)
        let elapsedComponents = calendar.dateComponents([.day], from: periodStart, to: effectiveToday)
        let daysElapsed: Int

        if referenceDate < periodStart {
            daysElapsed = 0
        } else {
            daysElapsed = min(daysInPeriod, max(1, (elapsedComponents.day ?? 0) + 1))
        }

        return SpendingVelocityData(
            periodStart: periodStart,
            periodEnd: periodEnd,
            daysInPeriod: daysInPeriod,
            daysElapsed: daysElapsed,
            actualSpent: totalSpent,
            budgetAssigned: budgetAssigned
        )
    }
}
