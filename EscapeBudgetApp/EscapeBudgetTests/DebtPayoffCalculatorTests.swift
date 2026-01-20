import Foundation
import Testing
@testable import EscapeBudget

@Suite("DebtPayoffCalculator Tests")
struct DebtPayoffCalculatorTests {

    // MARK: - Basic Calculation Tests

    @Test("Basic payoff calculation returns valid projection")
    func testBasicPayoffCalculation() {
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 5000,
            interestRate: 0.20,
            monthlyPayment: 150
        )

        #expect(result != nil)
        #expect(result!.monthsToPayoff > 0)
        #expect(result!.totalInterestPaid > 0)
        #expect(result!.schedule.count == result!.monthsToPayoff)
    }

    @Test("Known calculation produces expected results")
    func testKnownCalculation() {
        // $5000 at 20% APR with $150/month payment
        // Should take approximately 44-48 months
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 5000,
            interestRate: 0.20,
            monthlyPayment: 150
        )

        #expect(result != nil)
        #expect(result!.monthsToPayoff >= 40 && result!.monthsToPayoff <= 52)
        // Total interest should be roughly $1500-$2500
        #expect(result!.totalInterestPaid >= 1500 && result!.totalInterestPaid <= 2800)
    }

    @Test("Zero balance returns immediate payoff")
    func testZeroBalance() {
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 0,
            interestRate: 0.20,
            monthlyPayment: 150
        )

        #expect(result != nil)
        #expect(result!.monthsToPayoff == 0)
        #expect(result!.totalInterestPaid == 0)
        #expect(result!.schedule.isEmpty)
    }

    @Test("Zero payment returns nil")
    func testZeroPayment() {
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 5000,
            interestRate: 0.20,
            monthlyPayment: 0
        )

        #expect(result == nil)
    }

    @Test("Payment less than interest returns nil")
    func testPaymentLessThanInterest() {
        // $10000 at 20% = $166.67/month interest
        // Payment of $100 won't cover it
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 10000,
            interestRate: 0.20,
            monthlyPayment: 100
        )

        #expect(result == nil)
    }

    @Test("Zero interest rate calculates correctly")
    func testZeroInterestRate() {
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 1000,
            interestRate: 0,
            monthlyPayment: 100
        )

        #expect(result != nil)
        #expect(result!.monthsToPayoff == 10)
        #expect(result!.totalInterestPaid == 0)
    }

    @Test("Schedule entries are consistent")
    func testScheduleConsistency() {
        let result = DebtPayoffCalculator.calculatePayoff(
            balance: 1000,
            interestRate: 0.12,
            monthlyPayment: 100
        )

        #expect(result != nil)

        for (index, period) in result!.schedule.enumerated() {
            #expect(period.month == index + 1)
            #expect(period.payment > 0)
            #expect(period.principal >= 0)
            #expect(period.interest >= 0)
            #expect(period.remainingBalance >= 0)
        }

        // Last entry should have zero balance
        #expect(result!.schedule.last?.remainingBalance == 0)
    }

    // MARK: - Format Helper Tests

    @Test("formatMonths handles zero")
    func testFormatMonthsZero() {
        #expect(DebtPayoffCalculator.formatMonths(0) == "Paid off")
    }

    @Test("formatMonths handles single month")
    func testFormatMonthsSingle() {
        #expect(DebtPayoffCalculator.formatMonths(1) == "1 month")
    }

    @Test("formatMonths handles multiple months under a year")
    func testFormatMonthsUnderYear() {
        #expect(DebtPayoffCalculator.formatMonths(6) == "6 months")
        #expect(DebtPayoffCalculator.formatMonths(11) == "11 months")
    }

    @Test("formatMonths handles exact years")
    func testFormatMonthsExactYears() {
        #expect(DebtPayoffCalculator.formatMonths(12) == "1 year")
        #expect(DebtPayoffCalculator.formatMonths(24) == "2 years")
        #expect(DebtPayoffCalculator.formatMonths(36) == "3 years")
    }

    @Test("formatMonths handles years and months")
    func testFormatMonthsYearsAndMonths() {
        #expect(DebtPayoffCalculator.formatMonths(14) == "1y 2m")
        #expect(DebtPayoffCalculator.formatMonths(25) == "2y 1m")
        #expect(DebtPayoffCalculator.formatMonths(47) == "3y 11m")
    }

    // MARK: - Strategy Tests

    @Test("PayoffStrategy avalanche has correct properties")
    func testAvalancheStrategy() {
        let strategy = DebtPayoffCalculator.PayoffStrategy.avalanche
        #expect(strategy.rawValue == "Avalanche")
        #expect(strategy.description == "Pay highest interest first")
        #expect(strategy.icon == "chart.line.downtrend.xyaxis")
    }

    @Test("PayoffStrategy snowball has correct properties")
    func testSnowballStrategy() {
        let strategy = DebtPayoffCalculator.PayoffStrategy.snowball
        #expect(strategy.rawValue == "Snowball")
        #expect(strategy.description == "Pay smallest balance first")
        #expect(strategy.icon == "snowflake")
    }

    @Test("All strategies are iterable")
    func testStrategyIterable() {
        let strategies = DebtPayoffCalculator.PayoffStrategy.allCases
        #expect(strategies.count == 2)
        #expect(strategies.contains(.avalanche))
        #expect(strategies.contains(.snowball))
    }
}
