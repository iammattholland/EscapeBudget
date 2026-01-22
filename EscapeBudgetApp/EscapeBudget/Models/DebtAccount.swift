import Foundation
import SwiftData

@Model
final class DebtAccount: DemoDataTrackable {
    var name: String
    var currentBalance: Decimal
    var originalBalance: Decimal
    var interestRate: Decimal  // APR as decimal (e.g., 0.195 for 19.5%)
    var minimumPayment: Decimal
    var extraPayment: Decimal
    var colorHex: String
    var notes: String?
    var createdDate: Date
    var sortOrder: Int = 0
    var isDemoData: Bool = false

    // Optional link to an existing Account (credit card, loan, etc.)
    var linkedAccount: Account?

    init(
        name: String,
        currentBalance: Decimal,
        originalBalance: Decimal? = nil,
        interestRate: Decimal,
        minimumPayment: Decimal,
        extraPayment: Decimal = 0,
        colorHex: String = "FF3B30",
        notes: String? = nil,
        sortOrder: Int = 0,
        linkedAccount: Account? = nil,
        isDemoData: Bool = false
    ) {
        self.name = name
        self.currentBalance = currentBalance
        self.originalBalance = originalBalance ?? currentBalance
        self.interestRate = interestRate
        self.minimumPayment = minimumPayment
        self.extraPayment = extraPayment
        self.colorHex = colorHex
        self.notes = notes
        self.sortOrder = sortOrder
        self.linkedAccount = linkedAccount
        self.createdDate = Date()
        self.isDemoData = isDemoData
    }

    // MARK: - Computed Properties

    var totalMonthlyPayment: Decimal {
        minimumPayment + extraPayment
    }

    /// Returns the effective current balance - synced from linked account if available, otherwise the manual currentBalance
    var effectiveBalance: Decimal {
        if let account = linkedAccount {
            // Account balances for debt accounts are negative, so we take the absolute value
            return abs(account.balance)
        }
        return currentBalance
    }

    /// Indicates if this debt is synced with a linked account
    var isSyncedWithAccount: Bool {
        linkedAccount != nil
    }

    var isPaidOff: Bool {
        effectiveBalance <= 0
    }

    var payoffProgress: Double {
        guard originalBalance > 0 else { return 1.0 }
        let paid = originalBalance - effectiveBalance
        return min(1.0, max(0.0, Double(truncating: (paid / originalBalance) as NSNumber)))
    }

    var payoffProgressPercentage: Double {
        payoffProgress * 100
    }

    var monthlyInterestRate: Decimal {
        interestRate / 12
    }

    var interestRatePercentage: Decimal {
        interestRate * 100
    }

    /// Calculates months remaining to pay off the debt
    var monthsRemaining: Int? {
        guard effectiveBalance > 0, totalMonthlyPayment > 0 else { return isPaidOff ? 0 : nil }

        let monthlyRate = monthlyInterestRate

        // If payment is less than monthly interest, debt will never be paid off
        let monthlyInterest = effectiveBalance * monthlyRate
        guard totalMonthlyPayment > monthlyInterest else { return nil }

        if monthlyRate == 0 {
            // No interest - simple division
            return Int(ceil(Double(truncating: (effectiveBalance / totalMonthlyPayment) as NSNumber)))
        }

        // Standard amortization formula: n = -log(1 - (r * P) / M) / log(1 + r)
        // where P = principal, r = monthly rate, M = monthly payment
        let r = Double(truncating: monthlyRate as NSNumber)
        let P = Double(truncating: effectiveBalance as NSNumber)
        let M = Double(truncating: totalMonthlyPayment as NSNumber)

        let numerator = log(1 - (r * P) / M)
        let denominator = log(1 + r)

        guard denominator != 0, !numerator.isNaN, !numerator.isInfinite else { return nil }

        let months = -numerator / denominator
        return Int(ceil(months))
    }

    /// Projected payoff date based on current payment schedule
    var projectedPayoffDate: Date? {
        guard let months = monthsRemaining else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: Date())
    }

    /// Calculates total interest that will be paid over the life of the debt
    var projectedTotalInterest: Decimal? {
        guard let months = monthsRemaining, months > 0 else { return isPaidOff ? 0 : nil }

        var balance = effectiveBalance
        var totalInterest: Decimal = 0
        let monthlyRate = monthlyInterestRate

        for _ in 0..<months {
            let interest = balance * monthlyRate
            totalInterest += interest

            let principal = min(totalMonthlyPayment - interest, balance)
            balance -= principal

            if balance <= 0 { break }
        }

        return totalInterest
    }

    /// Smart insight text for display
    var smartInsight: String? {
        if isPaidOff {
            return "Paid off!"
        }

        if let months = monthsRemaining {
            if months == 1 {
                return "1 month to freedom"
            } else if months <= 12 {
                return "\(months) months to go"
            } else {
                let years = months / 12
                let remainingMonths = months % 12
                if remainingMonths == 0 {
                    return "\(years) year\(years == 1 ? "" : "s") to go"
                } else {
                    return "\(years)y \(remainingMonths)m to go"
                }
            }
        }

        // Payment too low warning
        let monthlyInterest = effectiveBalance * monthlyInterestRate
        if totalMonthlyPayment <= monthlyInterest {
            return "Payment doesn't cover interest"
        }

        return nil
    }

    /// Returns true if this is a high interest debt (> 15% APR)
    var isHighInterest: Bool {
        interestRate > 0.15
    }
}
