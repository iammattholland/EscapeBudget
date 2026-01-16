import Foundation
import SwiftData

@Model
final class MonthlyAccountTotal {
    /// The first day of the month (calendar month start).
    var monthStart: Date

    @Relationship
    var account: Account?

    /// Sum of `Transaction.amount` for this account within the month.
    var totalAmount: Decimal

    /// Count of transactions included in `totalAmount`.
    var transactionCount: Int

    /// Whether this account is tracking-only (captured at aggregation time).
    var isTrackingOnly: Bool

    var computedAt: Date

    init(
        monthStart: Date,
        account: Account,
        totalAmount: Decimal,
        transactionCount: Int,
        isTrackingOnly: Bool,
        computedAt: Date = Date()
    ) {
        self.monthStart = monthStart
        self.account = account
        self.totalAmount = totalAmount
        self.transactionCount = transactionCount
        self.isTrackingOnly = isTrackingOnly
        self.computedAt = computedAt
    }
}

