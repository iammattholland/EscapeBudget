import SwiftUI
import SwiftData
import Charts

struct CashFlowForecastView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("cashflow.horizonDays") private var horizonDays = 90
    @AppStorage("cashflow.includeIncome") private var includeIncome = true
    @AppStorage("cashflow.monthlyIncome") private var monthlyIncomeDouble: Double = 0
    @AppStorage("cashflow.includeChequing") private var includeChequing = true
    @AppStorage("cashflow.includeSavings") private var includeSavings = true
    @AppStorage("cashflow.includeOtherCash") private var includeOtherCash = true

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \RecurringPurchase.nextDate) private var recurringPurchases: [RecurringPurchase]
    @Query(sort: \PurchasePlan.purchaseDate) private var purchasePlans: [PurchasePlan]
    @Query(sort: \MonthlyCashflowTotal.monthStart, order: .reverse) private var monthlyTotals: [MonthlyCashflowTotal]
    @State private var suggestedMonthlyIncomeFromStats: Decimal = 0
    private let topChrome: AnyView?

    init(topChrome: AnyView? = nil) {
        self.topChrome = topChrome
    }

    private var horizonEnd: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: max(1, horizonDays), to: today) ?? today
    }

    private var includedCashAccounts: [Account] {
        accounts.filter { account in
            switch account.type {
            case .chequing:
                return includeChequing
            case .savings:
                return includeSavings
            case .other:
                return includeOtherCash
            case .creditCard, .investment, .lineOfCredit, .mortgage, .loans:
                return false
            }
        }
    }

    private var startingCash: Decimal {
        includedCashAccounts.reduce(0) { $0 + $1.balance }
    }

    private var suggestedMonthlyIncome: Decimal {
        suggestedMonthlyIncomeFromStats
    }

    private var monthlyIncome: Decimal {
        Decimal(monthlyIncomeDouble)
    }

    private var monthlyIncomeBinding: Binding<Decimal> {
        Binding(
            get: { Decimal(monthlyIncomeDouble) },
            set: { newValue in
                monthlyIncomeDouble = NSDecimalNumber(decimal: max(0, newValue)).doubleValue
            }
        )
    }

    private struct ForecastEvent: Identifiable {
        enum Kind {
            case income
            case bill
            case planned
        }

        let id: String
        let date: Date
        let title: String
        let kind: Kind
        let amount: Decimal // + inflow / - outflow
        let subtitle: String?
    }

    private var forecastEvents: [ForecastEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: horizonEnd)

        var events: [ForecastEvent] = []

        // Recurring bills (project occurrences)
        func advance(_ date: Date, frequency: RecurrenceFrequency) -> Date {
            switch frequency {
            case .weekly:
                return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
            case .biweekly:
                return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
            case .monthly:
                return calendar.date(byAdding: .month, value: 1, to: date) ?? date
            case .quarterly:
                return calendar.date(byAdding: .month, value: 3, to: date) ?? date
            case .yearly:
                return calendar.date(byAdding: .year, value: 1, to: date) ?? date
            }
        }

        for purchase in recurringPurchases where purchase.isActive {
            var date = calendar.startOfDay(for: purchase.nextDate)
            while date <= end {
                if date >= start {
                    let id = "recurring-\(purchase.persistentModelID)-\(date.timeIntervalSince1970)"
                    events.append(
                        ForecastEvent(
                            id: id,
                            date: date,
                            title: purchase.name,
                            kind: .bill,
                            amount: -abs(purchase.amount),
                            subtitle: purchase.recurrenceFrequency.rawValue
                        )
                    )
                }
                let next = advance(date, frequency: purchase.recurrenceFrequency)
                let advanced = calendar.startOfDay(for: next)
                if advanced == date { break }
                date = advanced
            }
        }

        // Planned purchases
        for plan in purchasePlans where !plan.isPurchased {
            guard let date = plan.purchaseDate else { continue }
            let day = calendar.startOfDay(for: date)
            guard day >= start && day <= end else { continue }
            let id = "planned-\(plan.persistentModelID)"
            events.append(
                ForecastEvent(
                    id: id,
                    date: day,
                    title: plan.itemName,
                    kind: .planned,
                    amount: -abs(plan.expectedPrice),
                    subtitle: "Planned"
                )
            )
        }

        // Income estimate (monthly, 1st of month)
        if includeIncome, monthlyIncome > 0 {
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            if cursor < start {
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? start
            }
            while cursor <= end {
                let id = "income-\(cursor.timeIntervalSince1970)"
                events.append(
                    ForecastEvent(
                        id: id,
                        date: cursor,
                        title: "Estimated Income",
                        kind: .income,
                        amount: abs(monthlyIncome),
                        subtitle: "Monthly estimate"
                    )
                )
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(86400)
            }
        }

        return events.sorted { $0.date < $1.date }
    }

    private struct BalancePoint: Identifiable {
        let id: TimeInterval
        let date: Date
        let balance: Double
    }

    private var balanceSeries: [BalancePoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: horizonEnd)

        let byDay = Dictionary(grouping: forecastEvents, by: { calendar.startOfDay(for: $0.date) })

        var points: [BalancePoint] = []
        var running = startingCash
        var day = start

        while day <= end {
            if let events = byDay[day] {
                for event in events {
                    running += event.amount
                }
            }

            points.append(
                BalancePoint(
                    id: day.timeIntervalSince1970,
                    date: day,
                    balance: NSDecimalNumber(decimal: running).doubleValue
                )
            )

            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86400)
        }

        return points
    }

    private var totals: (inflows: Decimal, outflows: Decimal, projectedEnd: Decimal, lowest: Decimal) {
        var inflows: Decimal = 0
        var outflows: Decimal = 0
        for event in forecastEvents {
            if event.amount >= 0 {
                inflows += event.amount
            } else {
                outflows += abs(event.amount)
            }
        }

        let endBalance = Decimal(balanceSeries.last?.balance ?? 0)
        let lowestBalance = Decimal(balanceSeries.map(\.balance).min() ?? 0)
        return (inflows, outflows, endBalance, lowestBalance)
    }

    var body: some View {
        ScrollView {
            AppChromeStack(topChrome: topChrome, scrollID: "PlanForecastHubView.scroll") {
                LazyVStack(spacing: AppDesign.Theme.Spacing.cardGap) {
                    summaryRow
                    chartCard
                    assumptionsCard
                    accountsCard
                    eventsCard
                }
                .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                .padding(.vertical, AppDesign.Theme.Spacing.tight)
            }
        }
        .coordinateSpace(name: "PlanForecastHubView.scroll")
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cash Flow")
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .onAppear {
            Task { @MainActor in
                await MonthlyCashflowTotalsService.ensureUpToDateAsync(modelContext: modelContext)
            }
            suggestedMonthlyIncomeFromStats = computeSuggestedMonthlyIncome()
            if monthlyIncomeDouble == 0, suggestedMonthlyIncome > 0 {
                monthlyIncomeDouble = NSDecimalNumber(decimal: suggestedMonthlyIncome).doubleValue
            }
        }
    }

    private func computeSuggestedMonthlyIncome() -> Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        let windowStart = calendar.date(from: calendar.dateComponents([.year, .month], from: threeMonthsAgo)) ?? threeMonthsAgo

        let fullMonthsIncome = monthlyTotals
            .filter { $0.monthStart >= windowStart && $0.monthStart < currentMonthStart }
            .reduce(Decimal.zero) { $0 + $1.incomeTotal }

        let partialCurrentMonthIncome: Decimal = {
            let standardRaw = TransactionKind.standard.rawValue
            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { tx in
                    tx.kindRawValue == standardRaw &&
                    tx.amount > 0 &&
                    tx.date >= currentMonthStart
                }
            )
            let txs = (try? modelContext.fetch(descriptor)) ?? []
            return txs
                .filter { $0.account?.isTrackingOnly != true }
                .filter { $0.category?.group?.type == .income }
                .reduce(Decimal.zero) { $0 + $1.amount }
        }()

        let totalIncome = fullMonthsIncome + partialCurrentMonthIncome
        guard totalIncome > 0 else { return 0 }
        return totalIncome / 3
    }

    private var summaryRow: some View {
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
            MetricCard(
                title: "Start",
                value: startingCash,
                currencyCode: currencyCode,
                tint: AppDesign.Colors.tint(for: appColorMode)
            )
            MetricCard(
                title: "End (\(horizonDays)d)",
                value: totals.projectedEnd,
                currencyCode: currencyCode,
                tint: totals.projectedEnd >= startingCash ? AppDesign.Colors.success(for: appColorMode) : AppDesign.Colors.warning(for: appColorMode)
            )
        }
    }

	    private var chartCard: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	            HStack {
	                Text("Cash Flow Forecast")
	                    .appSectionTitleText()
	                Spacer()
	                Picker("Range", selection: $horizonDays) {
	                    Text("30d").tag(30)
                    Text("60d").tag(60)
                    Text("90d").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if balanceSeries.isEmpty {
                ContentUnavailableView(
                    "No forecast data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Add recurring bills or planned purchases to see your projected balance.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppDesign.Theme.Spacing.relaxed)
            } else {
                Chart(balanceSeries) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppDesign.Colors.tint(for: appColorMode).opacity(0.22),
                                AppDesign.Colors.tint(for: appColorMode).opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number, format: .currency(code: currencyCode))
                                    .appCaption2Text()
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day(), centered: true)
                            .font(AppDesign.Theme.Typography.caption2)
                    }
                }
                .frame(height: 220)

                HStack(spacing: AppDesign.Theme.Spacing.tight) {
                    MetricPill(label: "In", value: totals.inflows, currencyCode: currencyCode, tint: AppDesign.Colors.success(for: appColorMode))
                    MetricPill(label: "Out", value: totals.outflows, currencyCode: currencyCode, tint: AppDesign.Colors.danger(for: appColorMode))
                    MetricPill(label: "Lowest", value: totals.lowest, currencyCode: currencyCode, tint: AppDesign.Colors.warning(for: appColorMode))
                }
                .padding(.top, AppDesign.Theme.Spacing.hairline)

                Text("This forecast uses your current cash balances plus upcoming recurring bills and planned purchases. Income is an estimate (optional).")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
        .appElevatedCardSurface()
    }

	    private var assumptionsCard: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	            Text("Assumptions")
	                .appSectionTitleText()

	            Toggle("Include income estimate", isOn: $includeIncome)

            if includeIncome {
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                    Text("Estimated monthly income")
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    TextField("Monthly income", value: monthlyIncomeBinding, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)

                    Button("Use last 3 months average") {
                        let suggested = suggestedMonthlyIncome
                        monthlyIncomeDouble = NSDecimalNumber(decimal: max(0, suggested)).doubleValue
                    }
                    .appSecondaryCTA()
                    .disabled(suggestedMonthlyIncome <= 0)
                }
            }
        }
        .appElevatedCardSurface()
    }

	    private var accountsCard: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	            Text("Starting Cash")
	                .appSectionTitleText()

            Toggle("Chequing", isOn: $includeChequing)
            Toggle("Savings", isOn: $includeSavings)
            Toggle("Other cash accounts", isOn: $includeOtherCash)

            if includedCashAccounts.isEmpty {
                Text("No cash accounts selected.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            } else {
	                ForEach(includedCashAccounts) { account in
	                    HStack {
	                        Label(account.name, systemImage: account.type.icon)
	                            .foregroundStyle(.primary)
	                        Spacer()
	                        Text(account.balance, format: .currency(code: currencyCode))
	                            .foregroundStyle(.secondary)
	                    }
	                    .font(AppDesign.Theme.Typography.secondaryBody)
	                }
	            }
	        }
	        .appElevatedCardSurface()
	    }

	    private var eventsCard: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	            HStack {
	                Text("Upcoming Events")
	                    .appSectionTitleText()
	                Spacer()
	                Text("\(forecastEvents.count)")
	                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            if forecastEvents.isEmpty {
                Text("Add recurring bills or planned purchases to see a cash flow timeline.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            } else {
                ForEach(forecastEvents.prefix(24)) { event in
                    HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.small) {
                        Circle()
                            .fill(color(for: event.kind).opacity(0.18))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: icon(for: event.kind))
                                    .appCaptionText()
                                    .foregroundStyle(color(for: event.kind))
                            )

	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
	                            Text(event.title)
	                                .appSecondaryBodyText()
	                                .fontWeight(.medium)

                            HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                                Text(event.date, format: .dateTime.month(.abbreviated).day().year())
                                if let subtitle = event.subtitle {
                                    Text("•")
                                    Text(subtitle)
                                }
                            }
                            .appCaption2Text()
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

	                        Text(event.amount, format: .currency(code: currencyCode))
	                            .appSecondaryBodyText()
	                            .fontWeight(.semibold)
	                            .foregroundStyle(event.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary)
	                            .monospacedDigit()
	                    }
                    .padding(.vertical, AppDesign.Theme.Spacing.micro)
                }

                if forecastEvents.count > 24 {
                    Text("Showing the next 24 events.")
                        .appCaption2Text()
                        .foregroundStyle(.secondary)
                        .padding(.top, AppDesign.Theme.Spacing.hairline)
                }
            }
        }
        .appElevatedCardSurface()
    }

    private func icon(for kind: ForecastEvent.Kind) -> String {
        switch kind {
        case .income: return "arrow.down.circle.fill"
        case .bill: return "calendar.badge.clock"
        case .planned: return "cart.fill"
        }
    }

    private func color(for kind: ForecastEvent.Kind) -> Color {
        switch kind {
        case .income: return AppDesign.Colors.success(for: appColorMode)
        case .bill: return AppDesign.Colors.warning(for: appColorMode)
        case .planned: return AppDesign.Colors.tint(for: appColorMode)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .appTitleText()
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .appElevatedCardSurface(stroke: tint.opacity(0.25))
    }
}

private struct MetricPill: View {
    let label: String
    let value: Decimal
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
            Text(label)
                .appCaption2Text()
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .appCaptionText()
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
        .padding(.horizontal, AppDesign.Theme.Spacing.small)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

#Preview {
    CashFlowForecastView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionHistoryEntry.self, TransactionTag.self, RecurringPurchase.self, PurchasePlan.self, CategoryGroup.self, Category.self, MonthlyCashflowTotal.self], inMemory: true)
}
