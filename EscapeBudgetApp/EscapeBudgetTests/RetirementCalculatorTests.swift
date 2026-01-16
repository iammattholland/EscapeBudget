import Testing
import Foundation
@testable import EscapeBudget

struct RetirementCalculatorTests {

    // MARK: - Future Value Tests

    @Test func testFutureValueWithNoContributions() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 0,
            monthlyReturn: 0.005,
            months: 120
        )

        let expected = 10000.0 * pow(1.005, 120.0)
        #expect(abs(result - expected) < 0.01)
    }

    @Test func testFutureValueWithNoGrowth() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 500,
            monthlyReturn: 0.0,
            months: 120
        )

        let expected = 10000.0 + (500.0 * 120.0)
        #expect(abs(result - expected) < 0.01)
    }

    @Test func testFutureValueWithContributionsAndGrowth() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 500,
            monthlyReturn: 0.005,
            months: 120
        )

        #expect(result > 10000)
        #expect(result > 10000 + (500 * 120))
    }

    @Test func testFutureValueZeroMonths() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 500,
            monthlyReturn: 0.005,
            months: 0
        )

        #expect(result == 10000)
    }

    @Test func testFutureValueNegativeReturn() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: -0.01,
            months: 12
        )

        let withoutContributions = 10000.0 * pow(1.0 - 0.01, 12.0)
        let withoutGrowth = 10000.0 + (100.0 * 12.0)
        #expect(result > withoutContributions)
        #expect(result < withoutGrowth)
    }

    @Test func testFutureValueLargeNumbers() {
        let result = RetirementMath.futureValue(
            presentValue: 1000000,
            monthlyContribution: 5000,
            monthlyReturn: 0.006,
            months: 360
        )

        #expect(result > 1000000)
        #expect(result.isFinite)
    }

    @Test func testFutureValueSmallReturn() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: 0.0001,
            months: 120
        )

        #expect(result > 10000)
        #expect(result < 25000)
    }

    @Test func testFutureValueNearZeroReturn() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: 0.0000000001,
            months: 120
        )

        let expected = 10000.0 + (100.0 * 120.0)
        #expect(abs(result - expected) < 1.0)
    }

    @Test func testFutureValueTypicalRetirementScenario() {
        let monthlyReturn = pow(1.07, 1.0 / 12.0) - 1.0

        let result = RetirementMath.futureValue(
            presentValue: 50000,
            monthlyContribution: 1000,
            monthlyReturn: monthlyReturn,
            months: 30 * 12
        )

        #expect(result > 1000000)
        #expect(result < 2000000)
    }

    // MARK: - Required Monthly Contribution Tests

    @Test func testRequiredContributionAlreadyMet() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 100000,
            targetValue: 50000,
            monthlyReturn: 0.005,
            months: 120
        )

        #expect(result == 0)
    }

    @Test func testRequiredContributionWithNoGrowth() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 10000,
            targetValue: 70000,
            monthlyReturn: 0.0,
            months: 120
        )

        let expected = (70000.0 - 10000.0) / 120.0
        #expect(abs(result - expected) < 0.01)
    }

    @Test func testRequiredContributionWithGrowth() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 50000,
            targetValue: 200000,
            monthlyReturn: 0.005,
            months: 120
        )

        #expect(result > 0)
        #expect(result < 2000)
        #expect(result.isFinite)
    }

    @Test func testRequiredContributionZeroMonths() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 10000,
            targetValue: 50000,
            monthlyReturn: 0.005,
            months: 0
        )

        #expect(result.isInfinite)
    }

    @Test func testRequiredContributionZeroTarget() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 10000,
            targetValue: 0,
            monthlyReturn: 0.005,
            months: 120
        )

        #expect(result == 0)
    }

    @Test func testRequiredContributionNegativeReturn() {
        let result = RetirementMath.requiredMonthlyContribution(
            presentValue: 10000,
            targetValue: 20000,
            monthlyReturn: -0.01,
            months: 120
        )

        #expect(result > 0)
        #expect(result.isFinite)
    }

    @Test func testRequiredContributionVerification() {
        let presentValue = 50000.0
        let targetValue = 150000.0
        let monthlyReturn = 0.005
        let months = 120

        let requiredContribution = RetirementMath.requiredMonthlyContribution(
            presentValue: presentValue,
            targetValue: targetValue,
            monthlyReturn: monthlyReturn,
            months: months
        )

        let futureValue = RetirementMath.futureValue(
            presentValue: presentValue,
            monthlyContribution: requiredContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(abs(futureValue - targetValue) < 1.0)
    }

    // MARK: - Months to Reach Target Tests

    @Test func testMonthsToReachTargetAlreadyMet() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 100000,
            monthlyContribution: 1000,
            monthlyReturn: 0.005,
            targetValue: 50000,
            maxMonths: 1200
        )

        #expect(result == 0)
    }

    @Test func testMonthsToReachTargetNoContributionNoGrowth() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 10000,
            monthlyContribution: 0,
            monthlyReturn: 0.0,
            targetValue: 20000,
            maxMonths: 1200
        )

        #expect(result == nil)
    }

    @Test func testMonthsToReachTargetWithContributionNoGrowth() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 10000,
            monthlyContribution: 1000,
            monthlyReturn: 0.0,
            targetValue: 20000,
            maxMonths: 1200
        )

        #expect(result == 10)
    }

    @Test func testMonthsToReachTargetWithGrowth() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 50000,
            monthlyContribution: 1000,
            monthlyReturn: 0.005,
            targetValue: 100000,
            maxMonths: 1200
        )

        #expect(result != nil)
        #expect(result! > 0)
        #expect(result! < 100)
    }

    @Test func testMonthsToReachTargetZeroTarget() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 10000,
            monthlyContribution: 1000,
            monthlyReturn: 0.005,
            targetValue: 0,
            maxMonths: 1200
        )

        #expect(result == 0)
    }

    @Test func testMonthsToReachTargetNegativeReturn() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 50000,
            monthlyContribution: 2000,
            monthlyReturn: -0.001,
            targetValue: 100000,
            maxMonths: 1200
        )

        #expect(result != nil)
        #expect(result! > 0)
    }

    @Test func testMonthsToReachTargetVerification() {
        let presentValue = 20000.0
        let monthlyContribution = 500.0
        let targetValue = 50000.0
        let monthlyReturn = 0.004

        let months = RetirementMath.monthsToReachTarget(
            presentValue: presentValue,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            targetValue: targetValue,
            maxMonths: 1200
        )

        #expect(months != nil)
        let futureValue = RetirementMath.futureValue(
            presentValue: presentValue,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            months: months ?? 0
        )

        #expect(futureValue >= targetValue - 100)
    }

    @Test func testMonthsToReachTargetSmallGap() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 99000,
            monthlyContribution: 1000,
            monthlyReturn: 0.005,
            targetValue: 100000,
            maxMonths: 1200
        )

        #expect(result == 1)
    }

    @Test func testMonthsToReachTargetLargeGap() {
        let result = RetirementMath.monthsToReachTarget(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: 0.006,
            targetValue: 500000,
            maxMonths: 12000
        )

        #expect(result != nil)
        #expect(result! > 100)
    }

    // MARK: - Safe Withdrawal Rate Tests

    @Test func testSafeWithdrawalRateStandard4Percent() {
        let targetPortfolio = 1000000.0
        let safeWithdrawalRate = 0.04
        let annualWithdrawal = targetPortfolio * safeWithdrawalRate

        #expect(annualWithdrawal == 40000.0)
    }

    @Test func testSafeWithdrawalRateCalculation() {
        let annualSpending = 50000.0
        let safeWithdrawalRate = 0.04
        let requiredPortfolio = annualSpending / safeWithdrawalRate

        #expect(requiredPortfolio == 1250000.0)
    }

    @Test func testSafeWithdrawalRateVariableRates() {
        let annualSpending = 60000.0

        let conservative = annualSpending / 0.03
        let standard = annualSpending / 0.04
        let aggressive = annualSpending / 0.05

        #expect(conservative == 2000000.0)
        #expect(standard == 1500000.0)
        #expect(aggressive == 1200000.0)
    }

    // MARK: - Monthly Return Conversion Tests

    @Test func testAnnualToMonthlyReturn() {
        let annualReturn = 0.07
        let monthlyReturn = pow(1 + annualReturn, 1.0 / 12.0) - 1.0

        #expect(monthlyReturn > 0.005)
        #expect(monthlyReturn < 0.006)

        let backToAnnual = pow(1 + monthlyReturn, 12.0) - 1.0
        #expect(abs(backToAnnual - annualReturn) < 0.0001)
    }

    @Test func testRealReturnAfterInflation() {
        let nominalReturn = 0.10
        let inflation = 0.03
        let realReturn = ((1 + nominalReturn) / (1 + inflation)) - 1

        #expect(realReturn > 0.06)
        #expect(realReturn < 0.07)
    }

    // MARK: - Edge Cases and Boundary Tests

    @Test func testVeryHighReturn() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: 0.1,
            months: 12
        )

        #expect(result > 10000)
        #expect(result.isFinite)
    }

    @Test func testVeryLongTimeHorizon() {
        let result = RetirementMath.futureValue(
            presentValue: 10000,
            monthlyContribution: 100,
            monthlyReturn: 0.005,
            months: 600
        )

        #expect(result > 10000)
        #expect(result.isFinite)
    }

    @Test func testZeroPresentValue() {
        let result = RetirementMath.futureValue(
            presentValue: 0,
            monthlyContribution: 1000,
            monthlyReturn: 0.005,
            months: 120
        )

        #expect(result > 0)
        #expect(result > 1000 * 120)
    }

    @Test func testLargeMonthlyContribution() {
        let result = RetirementMath.futureValue(
            presentValue: 0,
            monthlyContribution: 10000,
            monthlyReturn: 0.005,
            months: 360
        )

        #expect(result > 10000 * 360)
        #expect(result.isFinite)
    }

    // MARK: - Realistic Retirement Scenarios

    @Test func testYoungProfessional() {
        let age = 25
        let retirementAge = 65
        let years = retirementAge - age
        let months = years * 12

        let currentSavings = 10000.0
        let monthlyContribution = 500.0
        let realReturn = 0.05
        let monthlyReturn = pow(1 + realReturn, 1.0 / 12.0) - 1.0

        let futureValue = RetirementMath.futureValue(
            presentValue: currentSavings,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(futureValue > 500000)
        #expect(futureValue.isFinite)
    }

    @Test func testMidCareerProfessional() {
        let age = 40
        let retirementAge = 65
        let years = retirementAge - age
        let months = years * 12

        let currentSavings = 200000.0
        let monthlyContribution = 2000.0
        let realReturn = 0.05
        let monthlyReturn = pow(1 + realReturn, 1.0 / 12.0) - 1.0

        let futureValue = RetirementMath.futureValue(
            presentValue: currentSavings,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(futureValue > 1000000)
        #expect(futureValue.isFinite)
    }

    @Test func testLateCareerCatchUp() {
        let age = 50
        let retirementAge = 65
        let years = retirementAge - age
        let months = years * 12

        let currentSavings = 300000.0
        let targetSavings = 1000000.0
        let realReturn = 0.05
        let monthlyReturn = pow(1 + realReturn, 1.0 / 12.0) - 1.0

        let requiredContribution = RetirementMath.requiredMonthlyContribution(
            presentValue: currentSavings,
            targetValue: targetSavings,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(requiredContribution > 0)
        #expect(requiredContribution < 5000)
        #expect(requiredContribution.isFinite)
    }

    @Test func testEarlyRetirement() {
        let age = 35
        let retirementAge = 50
        let years = retirementAge - age
        let months = years * 12

        let currentSavings = 200000.0
        let targetSavings = 1500000.0
        let realReturn = 0.06
        let monthlyReturn = pow(1 + realReturn, 1.0 / 12.0) - 1.0

        let requiredContribution = RetirementMath.requiredMonthlyContribution(
            presentValue: currentSavings,
            targetValue: targetSavings,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(requiredContribution > 3000)
        #expect(requiredContribution.isFinite)
    }

    // MARK: - Precision Tests

    @Test func testCalculationPrecision() {
        let presentValue = 123456.78
        let monthlyContribution = 987.65
        let monthlyReturn = 0.005432
        let months = 123

        let futureValue = RetirementMath.futureValue(
            presentValue: presentValue,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(futureValue.isFinite)
        #expect(!futureValue.isNaN)
    }

    @Test func testRoundTripCalculation() {
        let presentValue = 50000.0
        let monthlyContribution = 1000.0
        let monthlyReturn = 0.005
        let months = 180

        let futureValue = RetirementMath.futureValue(
            presentValue: presentValue,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        let calculatedMonths = RetirementMath.monthsToReachTarget(
            presentValue: presentValue,
            monthlyContribution: monthlyContribution,
            monthlyReturn: monthlyReturn,
            targetValue: futureValue,
            maxMonths: 12000
        )

        #expect(calculatedMonths != nil)
        #expect(abs(Double(calculatedMonths ?? 0) - Double(months)) < 2.0)
    }

    @Test func testConsistencyAcrossCalculations() {
        let presentValue = 100000.0
        let targetValue = 500000.0
        let monthlyReturn = 0.006
        let months = 240

        let requiredContribution = RetirementMath.requiredMonthlyContribution(
            presentValue: presentValue,
            targetValue: targetValue,
            monthlyReturn: monthlyReturn,
            months: months
        )

        let achievedValue = RetirementMath.futureValue(
            presentValue: presentValue,
            monthlyContribution: requiredContribution,
            monthlyReturn: monthlyReturn,
            months: months
        )

        #expect(abs(achievedValue - targetValue) / targetValue < 0.001)
    }
}
