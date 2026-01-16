import Foundation
import SwiftData

@Model
final class MonthlyCashflowTotal {
    /// The first day of the month (calendar month start).
    var monthStart: Date

    /// Sum of income transactions (positive amounts) categorized under an Income category group.
    var incomeTotal: Decimal

    /// Sum of expenses as positive magnitude (absolute value of negative amounts).
    var expenseTotal: Decimal

    /// Count of standard transactions included in this month (excluding tracking-only accounts).
    var transactionCount: Int

    var computedAt: Date

    init(
        monthStart: Date,
        incomeTotal: Decimal,
        expenseTotal: Decimal,
        transactionCount: Int,
        computedAt: Date = Date()
    ) {
        self.monthStart = monthStart
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.transactionCount = transactionCount
        self.computedAt = computedAt
    }
}

