import Foundation
import SwiftData

struct CategoryMonthBudgetSummary {
    let startingAvailable: Decimal
    let budgeted: Decimal
    let spent: Decimal
    let endingAvailable: Decimal
    let carryoverToNextMonth: Decimal

    var effectiveLimitThisMonth: Decimal {
        startingAvailable + budgeted
    }
}

struct CategoryBudgetPeriodSummary {
    let startingAvailable: Decimal
    let budgeted: Decimal
    let spent: Decimal
    let endingAvailable: Decimal

    var effectiveLimitForPeriod: Decimal {
        startingAvailable + budgeted
    }
}

struct CategoryBudgetCalculator {
    private let calendar: Calendar
    private let transactions: [Transaction]
    private let spentByCategoryByMonthIndex: [PersistentIdentifier: [Int: Decimal]]
    private let earliestMonthIndexByCategoryID: [PersistentIdentifier: Int]
    private let budgetAmountByCategoryByMonthIndex: [PersistentIdentifier: [Int: Decimal]]

    init(
        transactions: [Transaction],
        monthlyBudgets: [MonthlyCategoryBudget] = [],
        calendar: Calendar = .current
    ) {
        self.calendar = calendar

        let filtered = transactions.filter { tx in
            tx.kind == .standard && tx.account?.isTrackingOnly != true
        }
        self.transactions = filtered

        var spentMap: [PersistentIdentifier: [Int: Decimal]] = [:]
        var earliestByCat: [PersistentIdentifier: Int] = [:]

        for tx in filtered {
            guard let categoryID = tx.category?.persistentModelID else { continue }
            let idx = CategoryBudgetCalculator.monthIndex(for: tx.date, calendar: calendar)
            earliestByCat[categoryID] = min(earliestByCat[categoryID] ?? idx, idx)

            if tx.amount < 0 {
                let spent = abs(tx.amount)
                var byMonth = spentMap[categoryID] ?? [:]
                byMonth[idx, default: 0] += spent
                spentMap[categoryID] = byMonth
            }
        }

        self.spentByCategoryByMonthIndex = spentMap
        self.earliestMonthIndexByCategoryID = earliestByCat

        var budgetMap: [PersistentIdentifier: [Int: Decimal]] = [:]
        for entry in monthlyBudgets {
            guard let categoryID = entry.category?.persistentModelID else { continue }
            let idx = CategoryBudgetCalculator.monthIndex(for: entry.monthStart, calendar: calendar)
            var byMonth = budgetMap[categoryID] ?? [:]
            byMonth[idx] = entry.amount
            budgetMap[categoryID] = byMonth
        }
        self.budgetAmountByCategoryByMonthIndex = budgetMap
    }

    static func monthIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 1
        return year * 12 + (month - 1)
    }

    func startOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    func endOfMonthExclusive(for monthStart: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: startOfMonth(for: monthStart)) ?? monthStart
    }

    private func monthStart(forMonthIndex monthIndex: Int) -> Date {
        let year = monthIndex / 12
        let month = (monthIndex % 12) + 1
        return calendar.date(from: DateComponents(year: year, month: month)) ?? Date.distantPast
    }

    private func carryoverValue(_ raw: Decimal, handling: CategoryOverspendHandling) -> Decimal {
        switch handling {
        case .carryNegative:
            return raw
        case .doNotCarry:
            return max(Decimal.zero, raw)
        }
    }

    private func baselineMonthIndex(for category: Category, fallbackMonthIndex: Int) -> Int {
        if let createdAt = category.createdAt {
            return CategoryBudgetCalculator.monthIndex(for: createdAt, calendar: calendar)
        }
        if let earliest = earliestMonthIndexByCategoryID[category.persistentModelID] {
            return earliest
        }
        return fallbackMonthIndex
    }

    private func activeMonthIndexRange(for category: Category, startIndex: Int, endIndex: Int) -> ClosedRange<Int>? {
        let createdIndex = baselineMonthIndex(for: category, fallbackMonthIndex: startIndex)
        let archivedIndex: Int = {
            guard let archivedAfter = category.archivedAfterMonthStart else { return Int.max }
            return CategoryBudgetCalculator.monthIndex(for: archivedAfter, calendar: calendar)
        }()

        let activeStart = max(startIndex, createdIndex)
        let activeEnd = min(endIndex, archivedIndex)
        guard activeEnd >= activeStart else { return nil }
        return activeStart...activeEnd
    }

    private func spent(for categoryID: PersistentIdentifier, monthIndex: Int) -> Decimal {
        spentByCategoryByMonthIndex[categoryID]?[monthIndex] ?? 0
    }

    private func budgetedAmount(for category: Category, monthIndex: Int) -> Decimal {
        if category.budgetType == .lumpSum {
            return 0
        }
        let monthStart = monthStart(forMonthIndex: monthIndex)
        guard category.isActive(inMonthStart: monthStart, calendar: calendar) else {
            return 0
        }
        if let override = budgetAmountByCategoryByMonthIndex[category.persistentModelID]?[monthIndex] {
            return override
        }
        return category.assigned
    }

    private func spent(for categoryID: PersistentIdentifier, in start: Date, through end: Date) -> Decimal {
        var total: Decimal = 0
        for tx in transactions {
            guard tx.date >= start && tx.date <= end else { continue }
            guard tx.category?.persistentModelID == categoryID else { continue }
            if tx.amount < 0 { total += abs(tx.amount) }
        }
        return total
    }

    private func startBalanceAtMonthStart(category: Category, monthIndex: Int) -> Decimal {
        guard category.group?.type == .expense else { return 0 }

        let targetMonthStart = monthStart(forMonthIndex: monthIndex)
        guard category.isActive(inMonthStart: targetMonthStart, calendar: calendar) else { return 0 }

        let baseline = baselineMonthIndex(for: category, fallbackMonthIndex: monthIndex)
        if monthIndex <= baseline { // treat baseline month as start at 0/pool
            switch category.budgetType {
            case .monthlyReset, .monthlyRollover:
                return 0
            case .lumpSum:
                return category.assigned
            }
        }

        var carry: Decimal
        switch category.budgetType {
        case .monthlyReset, .monthlyRollover:
            carry = 0
        case .lumpSum:
            carry = category.assigned
        }

        for idx in baseline..<(monthIndex) {
            let monthSpent = spent(for: category.persistentModelID, monthIndex: idx)
            let monthBudget = budgetedAmount(for: category, monthIndex: idx)
            let endRaw: Decimal
            switch category.budgetType {
            case .monthlyReset:
                endRaw = monthBudget - monthSpent
                carry = 0
            case .monthlyRollover:
                endRaw = carry + monthBudget - monthSpent
                carry = carryoverValue(endRaw, handling: category.overspendHandling)
            case .lumpSum:
                endRaw = carry - monthSpent
                carry = carryoverValue(endRaw, handling: category.overspendHandling)
            }
        }

        return carry
    }

    func monthSummary(for category: Category, monthStart: Date) -> CategoryMonthBudgetSummary {
        let normalizedMonthStart = startOfMonth(for: monthStart)
        let idx = CategoryBudgetCalculator.monthIndex(for: normalizedMonthStart, calendar: calendar)
        let monthSpent = spent(for: category.persistentModelID, monthIndex: idx)
        let monthBudget = budgetedAmount(for: category, monthIndex: idx)

        if !category.isActive(inMonthStart: normalizedMonthStart, calendar: calendar) {
            let ending = -monthSpent
            return CategoryMonthBudgetSummary(
                startingAvailable: 0,
                budgeted: 0,
                spent: monthSpent,
                endingAvailable: ending,
                carryoverToNextMonth: 0
            )
        }

        guard category.group?.type == .expense else {
            let ending = category.assigned - monthSpent
            return CategoryMonthBudgetSummary(
                startingAvailable: 0,
                budgeted: category.assigned,
                spent: monthSpent,
                endingAvailable: ending,
                carryoverToNextMonth: 0
            )
        }

        switch category.budgetType {
        case .monthlyReset:
            let ending = monthBudget - monthSpent
            return CategoryMonthBudgetSummary(
                startingAvailable: 0,
                budgeted: monthBudget,
                spent: monthSpent,
                endingAvailable: ending,
                carryoverToNextMonth: 0
            )

        case .monthlyRollover:
            let starting = startBalanceAtMonthStart(category: category, monthIndex: idx)
            let endingRaw = starting + monthBudget - monthSpent
            let carryover = carryoverValue(endingRaw, handling: category.overspendHandling)
            return CategoryMonthBudgetSummary(
                startingAvailable: starting,
                budgeted: monthBudget,
                spent: monthSpent,
                endingAvailable: endingRaw,
                carryoverToNextMonth: carryover
            )

        case .lumpSum:
            let starting = startBalanceAtMonthStart(category: category, monthIndex: idx)
            let endingRaw = starting - monthSpent
            let carryover = carryoverValue(endingRaw, handling: category.overspendHandling)
            return CategoryMonthBudgetSummary(
                startingAvailable: starting,
                budgeted: 0,
                spent: monthSpent,
                endingAvailable: endingRaw,
                carryoverToNextMonth: carryover
            )
        }
    }

    func periodSummary(for category: Category, start: Date, end: Date) -> CategoryBudgetPeriodSummary {
        let startMonthStart = startOfMonth(for: start)
        let startIndex = CategoryBudgetCalculator.monthIndex(for: startMonthStart, calendar: calendar)
        let endMonthStart = startOfMonth(for: end)
        let endIndex = CategoryBudgetCalculator.monthIndex(for: endMonthStart, calendar: calendar)
        let spentInFullRange = spent(for: category.persistentModelID, in: start, through: end)

        guard let activeRange = activeMonthIndexRange(for: category, startIndex: startIndex, endIndex: endIndex) else {
            let ending = -spentInFullRange
            return CategoryBudgetPeriodSummary(
                startingAvailable: 0,
                budgeted: 0,
                spent: spentInFullRange,
                endingAvailable: ending
            )
        }

        let activeStartMonthStart = monthStart(forMonthIndex: activeRange.lowerBound)
        let activeEndMonthStart = monthStart(forMonthIndex: activeRange.upperBound)
        let activeEndInclusive = endOfMonthExclusive(for: activeEndMonthStart).addingTimeInterval(-0.001)

        let effectiveStart = max(start, activeStartMonthStart)
        let effectiveEnd = min(end, activeEndInclusive)
        let spentInPeriod = spent(for: category.persistentModelID, in: effectiveStart, through: effectiveEnd)

        let monthsCount = max(1, (activeRange.upperBound - activeRange.lowerBound) + 1)

        guard category.group?.type == .expense else {
            let budgeted = category.assigned * Decimal(monthsCount)
            let ending = budgeted - spentInPeriod
            return CategoryBudgetPeriodSummary(
                startingAvailable: 0,
                budgeted: budgeted,
                spent: spentInPeriod,
                endingAvailable: ending
            )
        }

        switch category.budgetType {
        case .monthlyReset:
            var budgeted: Decimal = 0
            for idx in activeRange {
                budgeted += budgetedAmount(for: category, monthIndex: idx)
            }
            let ending = budgeted - spentInPeriod
            return CategoryBudgetPeriodSummary(
                startingAvailable: 0,
                budgeted: budgeted,
                spent: spentInPeriod,
                endingAvailable: ending
            )

        case .monthlyRollover:
            let starting = startBalanceAtMonthStart(category: category, monthIndex: activeRange.lowerBound)
            var budgeted: Decimal = 0
            for idx in activeRange {
                budgeted += budgetedAmount(for: category, monthIndex: idx)
            }
            let ending = starting + budgeted - spentInPeriod
            return CategoryBudgetPeriodSummary(
                startingAvailable: starting,
                budgeted: budgeted,
                spent: spentInPeriod,
                endingAvailable: ending
            )

        case .lumpSum:
            let starting = startBalanceAtMonthStart(category: category, monthIndex: activeRange.lowerBound)
            let ending = starting - spentInPeriod
            return CategoryBudgetPeriodSummary(
                startingAvailable: starting,
                budgeted: 0,
                spent: spentInPeriod,
                endingAvailable: ending
            )
        }
    }
}
