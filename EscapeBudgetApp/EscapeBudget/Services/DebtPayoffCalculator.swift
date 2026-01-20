import Foundation

enum DebtPayoffCalculator {

    // MARK: - Types

    struct PayoffProjection {
        let monthsToPayoff: Int
        let totalInterestPaid: Decimal
        let payoffDate: Date
        let schedule: [PaymentPeriod]
    }

    struct PaymentPeriod {
        let month: Int
        let payment: Decimal
        let principal: Decimal
        let interest: Decimal
        let remainingBalance: Decimal
    }

    enum PayoffStrategy: String, CaseIterable, Identifiable {
        case avalanche = "Avalanche"
        case snowball = "Snowball"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .avalanche:
                return "Pay highest interest first"
            case .snowball:
                return "Pay smallest balance first"
            }
        }

        var icon: String {
            switch self {
            case .avalanche:
                return "chart.line.downtrend.xyaxis"
            case .snowball:
                return "snowflake"
            }
        }
    }

    struct StrategyComparison {
        let avalanche: MultiDebtProjection
        let snowball: MultiDebtProjection
        let interestSaved: Decimal  // Avalanche saves this much vs snowball
    }

    struct MultiDebtProjection {
        let strategy: PayoffStrategy
        let totalMonthsToDebtFree: Int
        let totalInterestPaid: Decimal
        let debtFreeDate: Date
        let payoffOrder: [String]  // Debt names in order they get paid off
    }

    // MARK: - Single Debt Calculation

    /// Calculates payoff projection for a single debt
    static func calculatePayoff(
        balance: Decimal,
        interestRate: Decimal,
        monthlyPayment: Decimal
    ) -> PayoffProjection? {
        // Already paid off
        if balance <= 0 {
            return PayoffProjection(
                monthsToPayoff: 0,
                totalInterestPaid: 0,
                payoffDate: Date(),
                schedule: []
            )
        }

        // Can't pay off without payment
        guard monthlyPayment > 0 else { return nil }

        let monthlyRate = interestRate / 12

        // Check if payment covers interest
        let firstMonthInterest = balance * monthlyRate
        guard monthlyPayment > firstMonthInterest else { return nil }

        var schedule: [PaymentPeriod] = []
        var remainingBalance = balance
        var totalInterest: Decimal = 0
        var month = 0

        while remainingBalance > 0 && month < 600 {  // Cap at 50 years
            month += 1

            let interest = remainingBalance * monthlyRate
            let payment = min(monthlyPayment, remainingBalance + interest)
            let principal = payment - interest

            remainingBalance -= principal
            totalInterest += interest

            // Prevent negative balance due to rounding
            if remainingBalance < 0.01 {
                remainingBalance = 0
            }

            schedule.append(PaymentPeriod(
                month: month,
                payment: payment,
                principal: principal,
                interest: interest,
                remainingBalance: remainingBalance
            ))
        }

        let payoffDate = Calendar.current.date(byAdding: .month, value: month, to: Date()) ?? Date()

        return PayoffProjection(
            monthsToPayoff: month,
            totalInterestPaid: totalInterest,
            payoffDate: payoffDate,
            schedule: schedule
        )
    }

    // MARK: - Multi-Debt Strategy Comparison

    /// Compares avalanche vs snowball strategies for multiple debts
    static func compareStrategies(
        debts: [DebtAccount],
        extraBudget: Decimal = 0
    ) -> StrategyComparison? {
        let activeDebts = debts.filter { !$0.isPaidOff }
        guard !activeDebts.isEmpty else { return nil }

        let avalanche = calculateMultiDebtPayoff(
            debts: activeDebts,
            strategy: .avalanche,
            extraBudget: extraBudget
        )

        let snowball = calculateMultiDebtPayoff(
            debts: activeDebts,
            strategy: .snowball,
            extraBudget: extraBudget
        )

        guard let avalanche, let snowball else { return nil }

        let interestSaved = snowball.totalInterestPaid - avalanche.totalInterestPaid

        return StrategyComparison(
            avalanche: avalanche,
            snowball: snowball,
            interestSaved: interestSaved
        )
    }

    /// Calculates multi-debt payoff using a specific strategy
    static func calculateMultiDebtPayoff(
        debts: [DebtAccount],
        strategy: PayoffStrategy,
        extraBudget: Decimal
    ) -> MultiDebtProjection? {
        guard !debts.isEmpty else { return nil }

        // Create working copies of debt balances
        struct WorkingDebt {
            let name: String
            var balance: Decimal
            let interestRate: Decimal
            let minimumPayment: Decimal
        }

        var workingDebts = debts.map { debt in
            WorkingDebt(
                name: debt.name,
                balance: debt.currentBalance,
                interestRate: debt.interestRate,
                minimumPayment: debt.minimumPayment
            )
        }

        var totalInterest: Decimal = 0
        var month = 0
        var payoffOrder: [String] = []

        // Sort debts based on strategy for targeting extra payments
        func sortedByPriority(_ debts: [WorkingDebt]) -> [WorkingDebt] {
            switch strategy {
            case .avalanche:
                return debts.sorted { $0.interestRate > $1.interestRate }
            case .snowball:
                return debts.sorted { $0.balance < $1.balance }
            }
        }

        while !workingDebts.isEmpty && month < 600 {
            month += 1

            // Process each debt - apply interest and minimum payment
            for i in 0..<workingDebts.count {
                let monthlyRate = workingDebts[i].interestRate / 12
                let interest = workingDebts[i].balance * monthlyRate
                totalInterest += interest

                // Apply minimum payment
                let payment = min(workingDebts[i].minimumPayment, workingDebts[i].balance + interest)
                workingDebts[i].balance = workingDebts[i].balance + interest - payment
            }

            // Apply extra payment to highest priority debt
            let sorted = sortedByPriority(workingDebts)
            if let targetName = sorted.first(where: { $0.balance > 0 })?.name,
               let targetIndex = workingDebts.firstIndex(where: { $0.name == targetName }) {
                let extraPayment = min(extraBudget, workingDebts[targetIndex].balance)
                workingDebts[targetIndex].balance -= extraPayment
            }

            // Remove paid-off debts and record payoff order
            let paidOff = workingDebts.filter { $0.balance <= 0.01 }
            for debt in paidOff {
                if !payoffOrder.contains(debt.name) {
                    payoffOrder.append(debt.name)
                }
            }
            workingDebts.removeAll { $0.balance <= 0.01 }
        }

        let debtFreeDate = Calendar.current.date(byAdding: .month, value: month, to: Date()) ?? Date()

        return MultiDebtProjection(
            strategy: strategy,
            totalMonthsToDebtFree: month,
            totalInterestPaid: totalInterest,
            debtFreeDate: debtFreeDate,
            payoffOrder: payoffOrder
        )
    }

    // MARK: - Helpers

    /// Formats months as a readable string
    static func formatMonths(_ months: Int) -> String {
        if months == 0 {
            return "Paid off"
        } else if months == 1 {
            return "1 month"
        } else if months < 12 {
            return "\(months) months"
        } else {
            let years = months / 12
            let remainingMonths = months % 12
            if remainingMonths == 0 {
                return "\(years) year\(years == 1 ? "" : "s")"
            } else {
                return "\(years)y \(remainingMonths)m"
            }
        }
    }
}
