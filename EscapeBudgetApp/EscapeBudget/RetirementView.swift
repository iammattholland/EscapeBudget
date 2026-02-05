import SwiftUI
import SwiftData
import Charts

struct RetirementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.appColorMode) private var appColorMode

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("retirement.isConfigured") private var isConfigured = false
    @AppStorage("retirement.scenario") private var scenarioRawValue: String = RetirementScenario.yourPlan.rawValue

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query(sort: \MonthlyCashflowTotal.monthStart, order: .reverse) private var monthlyCashflowTotals: [MonthlyCashflowTotal]

    private let windowMonths: Int
    private let windowStartDate: Date

    @AppStorage("retirement.currentAge") private var currentAge: Int = 30
    @AppStorage("retirement.targetAge") private var targetAge: Int = 65
    @AppStorage("retirement.includeInvestmentAccounts") private var includeInvestmentAccounts = true
    @AppStorage("retirement.includeSavingsAccounts") private var includeSavingsAccounts = false
    @AppStorage("retirement.includeOtherPositiveAccounts") private var includeOtherPositiveAccounts = false

    @AppStorage("retirement.useSpendingFromTransactions") private var useSpendingFromTransactions = true
    @AppStorage("retirement.spendingMonthlyOverride") private var spendingMonthlyOverrideText = ""

    @AppStorage("retirement.useInferredContributions") private var useInferredContributions = true
    @AppStorage("retirement.monthlyContributionOverride") private var monthlyContributionOverrideText = ""

    @AppStorage("retirement.externalAssets") private var externalAssetsText = ""
    @AppStorage("retirement.otherIncomeMonthly") private var otherIncomeMonthlyText = ""

    @AppStorage("retirement.useManualTarget") private var useManualTarget = false
    @AppStorage("retirement.manualTarget") private var manualTargetText = ""

    @AppStorage("retirement.safeWithdrawalRate") private var safeWithdrawalRate = 0.04
    @AppStorage("retirement.realReturn") private var realReturn = 0.05

    @AppStorage("retirement.showAdvanced") private var showAdvanced = false

    @State private var showingAssumptionsHelp = false
    @State private var showingPlanSettings = false
    @State private var showingDeletePlanConfirm = false

    @State private var derivedCashflow: CashflowSnapshot = .init(income: 0, spending: 0)
    @State private var derivedStandardCount: Int = 0
    @State private var derivedInferredMonthlySpending: Decimal? = nil
    @State private var derivedInferredMonthlyContribution: Decimal? = nil
    @State private var isComputingDerived = false
    private let topChrome: AnyView?

    private enum RetirementScenario: String, CaseIterable, Identifiable {
        case yourPlan = "Your Plan"
        case conservative = "Conservative"
        case base = "Base"
        case aggressive = "Aggressive"

        var id: String { rawValue }

        var presetRealReturn: Double? {
            switch self {
            case .yourPlan: return nil
            case .conservative: return 0.03
            case .base: return 0.05
            case .aggressive: return 0.07
            }
        }

        var presetSafeWithdrawalRate: Double? {
            switch self {
            case .yourPlan: return nil
            case .conservative: return 0.035
            case .base: return 0.04
            case .aggressive: return 0.045
            }
        }
    }

    private var scenario: RetirementScenario {
        RetirementScenario(rawValue: scenarioRawValue) ?? .yourPlan
    }

    init(topChrome: (() -> AnyView)? = nil) {
        self.topChrome = topChrome?()
        let months = 12
        windowMonths = months

        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .month, value: -months, to: today) ?? today
        windowStartDate = start
        let standardRaw = TransactionKind.standard.rawValue
        let transferRaw = TransactionKind.transfer.rawValue

        _transactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= start
                    && (tx.kindRawValue == standardRaw || tx.kindRawValue == transferRaw)
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

	    var body: some View {
	        let showOnlyEmptyState = !isConfigured || transactions.isEmpty
	        Group {
            if showOnlyEmptyState {
                List {
                    if topChrome != nil {
                        AppChromeListRow(topChrome: topChrome, scrollID: "RetirementView.scroll")
                    }

	                    if isConfigured {
	                        noTransactionDataCard
	                            .listRowInsets(EdgeInsets())
	                            .listRowSeparator(.hidden)
	                            .listRowBackground(Color.clear)
	                    } else {
	                        setupCard
	                            .listRowInsets(EdgeInsets())
	                            .listRowSeparator(.hidden)
	                            .listRowBackground(Color.clear)
	                    }
                }
                .listStyle(.plain)
                .appListCompactSpacing()
                .scrollContentBackground(.hidden)
                .appLightModePageBackground()
                    .coordinateSpace(name: "RetirementView.scroll")
            } else {
                ScrollView {
                    AppChromeStack(topChrome: topChrome, scrollID: "RetirementView.scroll") {
                        LazyVStack(spacing: AppDesign.Theme.Spacing.cardGap) {
                            headerCard
                            snapshotCard
                            projectionCard
                            actionPlanCard
                            settingsCard
                            dataSourcesCard
                        }
                        .padding(.horizontal, AppDesign.Theme.Spacing.medium)
                        .padding(.vertical, AppDesign.Theme.Spacing.tight)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .coordinateSpace(name: "RetirementView.scroll")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Plan Settings", systemImage: "slider.horizontal.3") {
                        showingPlanSettings = true
                    }
                    Button("Assumptions", systemImage: "info.circle") {
                        showingAssumptionsHelp = true
                    }

                    if isConfigured {
                        Divider()
                        Button("Delete Plan", systemImage: "trash", role: .destructive) {
                            showingDeletePlanConfirm = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .imageScale(.large)
                }
                .tint(.black)
                .accessibilityLabel("Retirement Menu")
                .accessibilityIdentifier("retirement.menu")
            }
        }
        .alert("Delete retirement plan?", isPresented: $showingDeletePlanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Plan", role: .destructive) {
                resetRetirementPlan()
            }
        } message: {
            Text("This will clear your retirement plan settings and return you to the setup screen.")
        }
        .sheet(isPresented: $showingPlanSettings) {
            NavigationStack {
                RetirementPlanSettingsView()
            }
        }
        .sheet(isPresented: $showingAssumptionsHelp) {
            RetirementAssumptionsHelpView(
                safeWithdrawalRate: safeWithdrawalRate,
                realReturn: realReturn
            )
        }
        .onAppear {
            normalizeAgesIfNeeded()
            inferConfiguredIfNeeded()
        }
        .onChange(of: currentAge) { _, _ in
            normalizeAgesIfNeeded()
        }
        .onChange(of: targetAge) { _, _ in
            normalizeAgesIfNeeded()
        }
        .task(id: derivedComputationKey) {
            await recomputeDerived()
        }
    }

    private func resetRetirementPlan() {
        let defaults = UserDefaults.standard
        let keysToClear = [
            "retirement.isConfigured",
            "retirement.scenario",
            "retirement.currentAge",
            "retirement.targetAge",
            "retirement.includeInvestmentAccounts",
            "retirement.includeSavingsAccounts",
            "retirement.includeOtherPositiveAccounts",
            "retirement.useSpendingFromTransactions",
            "retirement.spendingMonthlyOverride",
            "retirement.useInferredContributions",
            "retirement.monthlyContributionOverride",
            "retirement.externalAssets",
            "retirement.otherIncomeMonthly",
            "retirement.useManualTarget",
            "retirement.manualTarget",
            "retirement.safeWithdrawalRate",
            "retirement.realReturn",
            "retirement.showAdvanced"
        ]
        for key in keysToClear {
            defaults.removeObject(forKey: key)
        }

        scenarioRawValue = RetirementScenario.yourPlan.rawValue
        currentAge = 30
        targetAge = 65
        includeInvestmentAccounts = true
        includeSavingsAccounts = false
        includeOtherPositiveAccounts = false

        useSpendingFromTransactions = true
        spendingMonthlyOverrideText = ""

        useInferredContributions = true
        monthlyContributionOverrideText = ""

        externalAssetsText = ""
        otherIncomeMonthlyText = ""

        useManualTarget = false
        manualTargetText = ""

        safeWithdrawalRate = 0.04
        realReturn = 0.05

        showAdvanced = false

        derivedCashflow = .init(income: 0, spending: 0)
        derivedStandardCount = 0
        derivedInferredMonthlySpending = nil
        derivedInferredMonthlyContribution = nil
        isComputingDerived = false

        isConfigured = false
    }

    // MARK: - Data Selection

    private var includedAccounts: [Account] {
        accounts.filter { account in
            if account.balance <= 0 { return false }

            switch account.type {
            case .investment:
                return includeInvestmentAccounts
            case .savings:
                return includeSavingsAccounts
            case .chequing, .creditCard, .lineOfCredit, .mortgage, .loans, .other:
                return includeOtherPositiveAccounts
            }
        }
    }

    private var portfolioBalanceFromAccounts: Decimal {
        includedAccounts.reduce(0) { $0 + max(0, $1.balance) }
    }

    private var externalAssets: Decimal {
        parseAmount(externalAssetsText) ?? 0
    }

    private var currentPortfolio: Decimal {
        max(0, portfolioBalanceFromAccounts + externalAssets)
    }

    private var otherIncomeMonthly: Decimal {
        max(0, parseAmount(otherIncomeMonthlyText) ?? 0)
    }

    private var otherIncomeAnnual: Decimal {
        otherIncomeMonthly * 12
    }

    private struct CashflowSnapshot {
        let income: Decimal
        let spending: Decimal

        var surplus: Decimal { income - spending }

        var savingsRate: Double? {
            guard income > 0 else { return nil }
            return Double(truncating: (surplus / income) as NSNumber)
        }
    }

    private var cashflow: CashflowSnapshot {
        derivedCashflow
    }

    private var inferredMonthlySpending: Decimal? {
        derivedInferredMonthlySpending
    }

    private var spendingGoalMonthly: Decimal {
        if useSpendingFromTransactions {
            return inferredMonthlySpending ?? 0
        }

        if let override = parseAmount(spendingMonthlyOverrideText), override > 0 {
            return override
        }

        return inferredMonthlySpending ?? 0
    }

    private var spendingGoalAnnual: Decimal {
        spendingGoalMonthly * 12
    }

    private var requiredAnnualFromPortfolio: Decimal {
        max(0, spendingGoalAnnual - otherIncomeAnnual)
    }

    private var requiredPortfolio: Decimal {
        if useManualTarget, let manual = parseAmount(manualTargetText), manual > 0 {
            return manual
        }

        guard activeSafeWithdrawalRate > 0 else { return 0 }
        return requiredAnnualFromPortfolio / Decimal(activeSafeWithdrawalRate)
    }

    private var yearsToRetirement: Int {
        max(0, targetAge - currentAge)
    }

    private var monthsToRetirement: Int {
        max(0, yearsToRetirement * 12)
    }

    private var includedAccountIDs: Set<PersistentIdentifier> {
        Set(includedAccounts.map(\.persistentModelID))
    }

    private var inferredMonthlyContribution: Decimal? {
        derivedInferredMonthlyContribution
    }

    private var monthlyContribution: Decimal {
        if useInferredContributions {
            return inferredMonthlyContribution ?? 0
        }

        if let override = parseAmount(monthlyContributionOverrideText), override > 0 {
            return override
        }

        return inferredMonthlyContribution ?? 0
    }

    // MARK: - Projection

    private var monthlyRealReturn: Double {
        pow(1 + max(-0.99, activeRealReturn), 1.0 / 12.0) - 1.0
    }

    private var projectedPortfolioAtRetirement: Decimal {
        guard monthsToRetirement > 0 else { return currentPortfolio }
        let fv = RetirementMath.futureValue(
            presentValue: currentPortfolio.doubleValue,
            monthlyContribution: monthlyContribution.doubleValue,
            monthlyReturn: monthlyRealReturn,
            months: monthsToRetirement
        )
        return Decimal(fv)
    }

    private var progressFraction: Double {
        guard requiredPortfolio > 0 else { return 1 }
        return min(1, currentPortfolio.doubleValue / requiredPortfolio.doubleValue)
    }

    private var projectedFraction: Double {
        guard requiredPortfolio > 0 else { return 1 }
        return min(1, projectedPortfolioAtRetirement.doubleValue / requiredPortfolio.doubleValue)
    }

    private enum RetirementStatus {
        case noPlan
        case ahead
        case onTrack
        case behind
    }

    private var status: RetirementStatus {
        guard isConfigured else { return .noPlan }
        guard targetAge > currentAge else { return .noPlan }
        guard requiredPortfolio > 0 else { return .noPlan }

        let ratio = projectedPortfolioAtRetirement.doubleValue / requiredPortfolio.doubleValue
        if ratio >= 1.10 { return .ahead }
        if ratio >= 1.0 { return .onTrack }
        return .behind
    }

    private var statusTint: Color {
        switch status {
        case .ahead, .onTrack:
            return AppDesign.Colors.success(for: appColorMode)
        case .behind:
            return AppDesign.Colors.warning(for: appColorMode)
        case .noPlan:
            return AppDesign.Colors.tint(for: appColorMode)
        }
    }

    private var projectionSeries: [RetirementProjectionPoint] {
        guard yearsToRetirement > 0 else {
            return [RetirementProjectionPoint(age: currentAge, value: currentPortfolio.doubleValue)]
        }

        return (0...yearsToRetirement).map { yearOffset in
            let months = yearOffset * 12
            let value = RetirementMath.futureValue(
                presentValue: currentPortfolio.doubleValue,
                monthlyContribution: monthlyContribution.doubleValue,
                monthlyReturn: monthlyRealReturn,
                months: months
            )
            return RetirementProjectionPoint(age: currentAge + yearOffset, value: value)
        }
    }

    private var monthsToReachGoal: Int? {
        guard requiredPortfolio > 0 else { return nil }
        return RetirementMath.monthsToReachTarget(
            presentValue: currentPortfolio.doubleValue,
            monthlyContribution: monthlyContribution.doubleValue,
            monthlyReturn: monthlyRealReturn,
            targetValue: requiredPortfolio.doubleValue,
            maxMonths: 1200
        )
    }

    private var estimatedRetirementAgeAtGoal: Int? {
        guard let monthsToReachGoal else { return nil }
        return currentAge + (monthsToReachGoal / 12)
    }

    private var recommendedMonthlyContribution: Decimal? {
        guard requiredPortfolio > 0 else { return nil }
        guard monthsToRetirement > 0 else { return nil }
        let required = RetirementMath.requiredMonthlyContribution(
            presentValue: currentPortfolio.doubleValue,
            targetValue: requiredPortfolio.doubleValue,
            monthlyReturn: monthlyRealReturn,
            months: monthsToRetirement
        )
        guard required.isFinite else { return nil }
        return Decimal(max(0, required))
    }

    private var sustainableSpendingMonthlyAtRetirement: Decimal? {
        guard activeSafeWithdrawalRate > 0 else { return nil }
        let sustainableAnnual = projectedPortfolioAtRetirement * Decimal(activeSafeWithdrawalRate) + otherIncomeAnnual
        return max(0, sustainableAnnual / 12)
    }

    private var activeRealReturn: Double {
        scenario.presetRealReturn ?? realReturn
    }

    private var activeSafeWithdrawalRate: Double {
        scenario.presetSafeWithdrawalRate ?? safeWithdrawalRate
    }

    private var isPreviewingScenarioPreset: Bool {
        scenario != .yourPlan
    }

    // MARK: - UI

    private var headerCard: some View {
        RetirementCard {
	            HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.tight) {
	                ZStack {
	                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
	                        .fill(statusTint.opacity(0.12))
                    Image(systemName: "sparkles")
                        .appTitleText()
                        .foregroundStyle(statusTint)
                }
	                .frame(width: 44, height: 44)

	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
	                    Text("Retirement")
	                        .appSectionTitleText()
	                    Text("Turn your real spending into a clear number, a projection, and one next best action.")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                        .fixedSize(horizontal: false, vertical: true)
	                }

                Spacer()

                Button {
                    showingAssumptionsHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .appTitleText()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About assumptions")
            }
        }
    }

    private var setupCard: some View {
        EmptyDataCard(
            systemImage: "calendar.badge.plus",
            title: "Set Up Plan",
            message: "Add your ages, what counts as retirement savings, and your spending target to unlock projections.",
            actionTitle: "Set Up Plan"
        ) {
            showingPlanSettings = true
        }
    }

    private var noTransactionDataCard: some View {
        EmptyDataCard(
            systemImage: "chart.line.uptrend.xyaxis",
            title: "No Data Yet",
            message: "Add your first transaction to start generating retirement projections.",
            actionTitle: "Add Transaction"
        ) {
            navigator.addTransaction()
        }
    }

    private var snapshotCard: some View {
        RetirementCard {
            HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.cardGap) {
                RetirementRingProgress(
                    progress: progressFraction,
                    tint: statusTint
                )

	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	                    HStack(alignment: .firstTextBaseline) {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Text("Your Number")
                                .appSectionTitleText()
                            Text(requiredPortfolio, format: .currency(code: currencyCode))
                                .appDisplayText(AppDesign.Theme.DisplaySize.xxLarge, weight: .bold)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }

                        Spacer()

                        Text(statusLabel)
                            .appCaptionStrongText()
                            .foregroundStyle(statusTint)
                            .padding(.horizontal, AppDesign.Theme.Spacing.small)
                            .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
                            .background(
                                Capsule()
                                    .fill(statusTint.opacity(0.12))
                            )
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppDesign.Theme.Spacing.small) {
                        RetirementMetricTile(
                            title: "Today",
                            value: compactCurrency(currentPortfolio),
                            subtitle: "Included assets",
                            tint: statusTint
                        )
                        RetirementMetricTile(
                            title: "At \(targetAge)",
                            value: compactCurrency(projectedPortfolioAtRetirement),
                            subtitle: "Projected",
                            tint: statusTint
                        )
                    }

                    if let estimatedRetirementAgeAtGoal, monthsToRetirement > 0 {
                        RetirementInlineMessage(
                            icon: status == .behind ? "clock.arrow.circlepath" : "checkmark.seal.fill",
                            tint: statusTint,
                            text: status == .behind
                                ? "At your current pace, you reach your number around age \(estimatedRetirementAgeAtGoal)."
                                : "You’re projected to hit your number by about age \(estimatedRetirementAgeAtGoal)."
                        )
                    }

                    NavigationLink {
                        RetirementAccountsDetailView(
                            accounts: accounts,
                            currencyCode: currencyCode,
                            includeInvestmentAccounts: includeInvestmentAccounts,
                            includeSavingsAccounts: includeSavingsAccounts,
                            includeOtherPositiveAccounts: includeOtherPositiveAccounts,
                            externalAssets: externalAssets
                        )
                    } label: {
                        HStack(spacing: AppDesign.Theme.Spacing.compact) {
                            Text("What’s included")
                                .appSecondaryBodyStrongText()
                            Spacer()
                            Image(systemName: "chevron.right")
                                .appCaptionStrongText()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, AppDesign.Theme.Spacing.hairline)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var projectionCard: some View {
	        RetirementCard {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	                HStack {
	                    Text("Projection")
	                        .appSectionTitleText()
	                    Spacer()
	                    Text("\(yearsToRetirement) yr")
	                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                    Picker("Scenario", selection: $scenarioRawValue) {
                        ForEach(RetirementScenario.allCases) { item in
                            Text(item.rawValue).tag(item.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isPreviewingScenarioPreset {
                        HStack(spacing: AppDesign.Theme.Spacing.small) {
                            Text("Previewing \(scenario.rawValue) preset.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Apply to Plan") {
                                if let presetReturn = scenario.presetRealReturn {
                                    realReturn = presetReturn
                                }
                                if let presetSWR = scenario.presetSafeWithdrawalRate {
                                    safeWithdrawalRate = presetSWR
                                }
                                scenarioRawValue = RetirementScenario.yourPlan.rawValue
                                isConfigured = true
                            }
                            .appCaptionStrongText()
                            .appSecondaryCTA()
                        }
                    }
                }

	                if projectionSeries.count < 2 {
	                    Text("Add at least one year until retirement to see a projection.")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                } else {
	                    Chart {
                        ForEach(projectionBandSeries) { point in
                            AreaMark(
                                x: .value("Age", point.age),
                                yStart: .value("Low", point.low),
                                yEnd: .value("High", point.high)
                            )
                            .foregroundStyle(statusTint.opacity(0.14))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(projectionSeries) { point in
                            LineMark(
                                x: .value("Age", point.age),
                                y: .value("Portfolio", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(statusTint.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }

                        if requiredPortfolio > 0 {
                            RuleMark(y: .value("Target", requiredPortfolio.doubleValue))
                                .foregroundStyle(Color.primary.opacity(0.18))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Target \(compactCurrency(requiredPortfolio))")
                                        .appCaption2Text()
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 220)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisTick()
                                .foregroundStyle(.secondary.opacity(0.35))
                            AxisValueLabel {
                                if let y = value.as(Double.self) {
                                    Text(compactCurrency(Decimal(y)))
                                        .appCaption2Text()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.primary.opacity(0.04))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month().day())
                                        .appCaption2Text()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: AppDesign.Theme.Spacing.small) {
                    RetirementPill(
                        icon: "arrow.up.right.circle.fill",
                        title: "Return",
                        value: "\(Int(activeRealReturn * 100))%/yr",
                        tint: AppDesign.Colors.tint(for: appColorMode)
                    )
                    RetirementPill(
                        icon: "percent",
                        title: "SWR",
                        value: "\(String(format: "%.1f", activeSafeWithdrawalRate * 100))%",
                        tint: AppDesign.Colors.warning(for: appColorMode)
                    )
                }
            }
        }
    }

	    private var actionPlanCard: some View {
	        RetirementCard {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	                Text("Next Best Action")
	                    .appSectionTitleText()

	                if status == .noPlan {
	                    Text("Set your ages and pick which accounts to include to get a personalized plan.")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                } else {
	                    actionPlanContent
	                }
            }
        }
    }

    private var actionPlanContent: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
            if status == .behind, let recommendedMonthlyContribution {
                let delta = max(0, recommendedMonthlyContribution - monthlyContribution)

                RetirementActionCard(
                    title: "Increase contributions",
                    subtitle: "To reach your target by age \(targetAge), aim for about \(formatCurrency(recommendedMonthlyContribution))/mo.",
                    detail: delta > 0 ? "That’s \(formatCurrency(delta))/mo more than your current pace." : nil,
                    tint: AppDesign.Colors.tint(for: appColorMode),
                    primaryButtonTitle: "Use \(formatCurrency(recommendedMonthlyContribution))/mo",
                    primaryAction: {
                        useInferredContributions = false
                        monthlyContributionOverrideText = plainAmountString(recommendedMonthlyContribution)
                    }
                )
            } else if status == .onTrack || status == .ahead {
                RetirementInlineMessage(
                    icon: "checkmark.seal.fill",
                    tint: AppDesign.Colors.success(for: appColorMode),
                    text: "You’re on track for your plan. Automate your monthly contribution so you don’t rely on willpower."
                )
            }

            if let sustainable = sustainableSpendingMonthlyAtRetirement, spendingGoalMonthly > 0, sustainable < spendingGoalMonthly {
                let delta = spendingGoalMonthly - sustainable
                RetirementActionCard(
                    title: "Adjust the spend goal",
                    subtitle: "At your current plan, a sustainable retirement budget is about \(formatCurrency(sustainable))/mo.",
                    detail: "That’s \(formatCurrency(delta))/mo below your current goal.",
                    tint: AppDesign.Colors.warning(for: appColorMode),
                    primaryButtonTitle: "Use \(formatCurrency(sustainable))/mo",
                    primaryAction: {
                        useSpendingFromTransactions = false
                        spendingMonthlyOverrideText = plainAmountString(sustainable)
                    }
                )
            }

            if let savingsRate = cashflow.savingsRate {
                RetirementInlineMessage(
                    icon: "chart.line.uptrend.xyaxis",
                    tint: statusTint,
                    text: "Your last \(windowMonths) months savings rate is about \(Int(max(-1, min(1, savingsRate)) * 100))%. Small, consistent improvements compound."
                )
            } else {
                RetirementInlineMessage(
                    icon: "doc.text.magnifyingglass",
                    tint: statusTint,
                    text: "Add a few months of transactions to unlock data-driven insights (spending, savings rate, contribution pace)."
                )
            }
        }
    }

	    private var settingsCard: some View {
	        RetirementCard {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	                HStack {
	                    Text("Plan Settings")
	                        .appSectionTitleText()
	                    Spacer()
	                    Button(showAdvanced ? "Less" : "More") {
	                        withAnimation(.snappy) { showAdvanced.toggle() }
                    }
                    .appCaptionStrongText()
                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                    .buttonStyle(.plain)
                }

                agePickers

                accountInclusionToggles

                Divider()

                spendGoalControls

                Divider()

                contributionControls

                if showAdvanced {
                    Divider()
                    advancedControls
                }
            }
        }
    }

	    private var dataSourcesCard: some View {
	        RetirementCard {
	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	                Text("Data")
	                    .appSectionTitleText()

                RetirementKeyValueRow(
                    title: "Spending source",
                    value: useSpendingFromTransactions ? "Last \(windowMonths) months average" : "Manual goal"
                )
                RetirementKeyValueRow(
                    title: "Contribution source",
                    value: useInferredContributions ? "Estimated from activity" : "Manual goal"
                )
                RetirementKeyValueRow(
                    title: "Accounts included",
                    value: "\(includedAccounts.count) account\(includedAccounts.count == 1 ? "" : "s")"
                )

                Text("Projections are estimates and use real (inflation-adjusted) return assumptions.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }

	    private var agePickers: some View {
	        VStack(spacing: AppDesign.Theme.Spacing.small) {
	            Stepper {
	                HStack {
                    Text("Current age")
	                    Spacer()
	                    Text("\(currentAge)")
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)
	                }
	            } onIncrement: {
	                currentAge = min(currentAge + 1, 80)
	            } onDecrement: {
                currentAge = max(currentAge - 1, 18)
            }

            Stepper {
                HStack {
                    Text("Retire at")
	                    Spacer()
	                    Text("\(targetAge)")
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)
	                }
	            } onIncrement: {
	                targetAge = min(targetAge + 1, 80)
	            } onDecrement: {
                targetAge = max(targetAge - 1, 18)
            }
	        }
	        .font(AppDesign.Theme.Typography.secondaryBody)
	    }

	    private var accountInclusionToggles: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	            Text("Include accounts")
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)

            Toggle("Investment", isOn: $includeInvestmentAccounts)
            Toggle("Savings", isOn: $includeSavingsAccounts)
            Toggle("Other positive balances", isOn: $includeOtherPositiveAccounts)
	        }
	        .font(AppDesign.Theme.Typography.secondaryBody)
	    }

	    private var spendGoalControls: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	            Text("Retirement spending goal")
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)

            Picker("Spending goal", selection: Binding(
                get: { useSpendingFromTransactions ? 0 : 1 },
                set: { useSpendingFromTransactions = ($0 == 0) }
            )) {
                Text("Auto").tag(0)
                Text("Manual").tag(1)
            }
            .pickerStyle(.segmented)

	            if useSpendingFromTransactions {
	                Text("Estimated at \(formatCurrency(spendingGoalMonthly))/mo from your last \(windowMonths) months of spending.")
	                    .appCaptionText()
	                    .foregroundStyle(.secondary)
	            } else {
                HStack(spacing: AppDesign.Theme.Spacing.small) {
                    TextField("Monthly spend", text: $spendingMonthlyOverrideText)
                        .keyboardType(.decimalPad)
                    Text("/mo")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
	                }
	                .font(AppDesign.Theme.Typography.secondaryBody)
	            }
	        }
	    }

	    private var contributionControls: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	            Text("Monthly contributions")
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)

            Picker("Contribution goal", selection: Binding(
                get: { useInferredContributions ? 0 : 1 },
                set: { useInferredContributions = ($0 == 0) }
            )) {
                Text("Auto").tag(0)
                Text("Manual").tag(1)
            }
            .pickerStyle(.segmented)

	            if useInferredContributions {
	                Text("Estimated at \(formatCurrency(monthlyContribution))/mo from transfers into included accounts.")
	                    .appCaptionText()
	                    .foregroundStyle(.secondary)
	            } else {
                HStack(spacing: AppDesign.Theme.Spacing.small) {
                    TextField("Monthly contribution", text: $monthlyContributionOverrideText)
                        .keyboardType(.decimalPad)
                    Text("/mo")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
	                }
	                .font(AppDesign.Theme.Typography.secondaryBody)
	            }
	        }
	    }

	    private var advancedControls: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	            Text("Advanced assumptions")
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	                HStack {
	                    Text("Safe withdrawal rate")
	                    Spacer()
	                    Text("\(String(format: "%.1f", safeWithdrawalRate * 100))%")
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)
	                }
                Slider(value: $safeWithdrawalRate, in: 0.025...0.05, step: 0.001)
                    .tint(AppDesign.Colors.warning(for: appColorMode))
            }

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	                HStack {
	                    Text("Real return (after inflation)")
	                    Spacer()
	                    Text("\(Int(realReturn * 100))%")
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)
	                }
                Slider(value: $realReturn, in: 0.00...0.08, step: 0.0025)
                    .tint(AppDesign.Colors.tint(for: appColorMode))
            }

	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	                Toggle("Set my own target", isOn: $useManualTarget)
	                    .font(AppDesign.Theme.Typography.secondaryBody)

	                if useManualTarget {
	                    TextField("Target portfolio", text: $manualTargetText)
	                        .keyboardType(.decimalPad)
	                        .font(AppDesign.Theme.Typography.secondaryBody)
	                } else {
	                    Text("Target is calculated from your spending goal and safe withdrawal rate.")
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                Text("Other income at retirement (optional)")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
	                HStack(spacing: AppDesign.Theme.Spacing.small) {
	                    TextField("Monthly pension/SS", text: $otherIncomeMonthlyText)
	                        .keyboardType(.decimalPad)
	                    Text("/mo")
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
	                }
	                .font(AppDesign.Theme.Typography.secondaryBody)
	            }

	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	                Text("External retirement assets (optional)")
	                    .appCaptionText()
	                    .foregroundStyle(.secondary)
	                TextField("Other accounts", text: $externalAssetsText)
	                    .keyboardType(.decimalPad)
	                    .font(AppDesign.Theme.Typography.secondaryBody)
	            }
	        }
	        .font(AppDesign.Theme.Typography.secondaryBody)
	    }

    private var statusLabel: String {
        switch status {
        case .ahead:
            return "Ahead"
        case .onTrack:
            return "On Track"
        case .behind:
            return "Behind"
        case .noPlan:
            return "Set Up"
        }
    }

    private func normalizeAgesIfNeeded() {
        currentAge = min(max(currentAge, 18), 80)
        targetAge = min(max(targetAge, currentAge + 1), 80)
    }

    private var derivedComputationKey: String {
        let newest = transactions.first?.date.timeIntervalSince1970 ?? 0
        let oldest = transactions.last?.date.timeIntervalSince1970 ?? 0
        return [
            isConfigured ? "1" : "0",
            "\(transactions.count)",
            "\(newest)",
            "\(oldest)",
            "\(includedAccountIDs.count)",
            includeInvestmentAccounts ? "1" : "0",
            includeSavingsAccounts ? "1" : "0",
            includeOtherPositiveAccounts ? "1" : "0"
        ].joined(separator: "|")
    }

    @MainActor
    private func recomputeDerived() async {
        guard isConfigured else {
            derivedCashflow = .init(income: 0, spending: 0)
            derivedStandardCount = 0
            derivedInferredMonthlySpending = nil
            derivedInferredMonthlyContribution = nil
            return
        }

        if isComputingDerived { return }
        isComputingDerived = true
        defer { isComputingDerived = false }

        await MonthlyCashflowTotalsService.ensureUpToDateAsync(modelContext: modelContext)

        let start = windowStartDate
        let end = Date()
        let calendar = Calendar.current

        let startMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end

        let fullMonthsTotals = monthlyCashflowTotals.filter { entry in
            entry.monthStart >= startMonthStart && entry.monthStart < currentMonthStart
        }

        var income: Decimal = fullMonthsTotals.reduce(Decimal.zero) { $0 + $1.incomeTotal }
        var spending: Decimal = fullMonthsTotals.reduce(Decimal.zero) { $0 + $1.expenseTotal }
        var standardCount = fullMonthsTotals.reduce(0) { $0 + $1.transactionCount }

        // Add current month partial (to match previous behavior).
        for tx in transactions {
            guard tx.date >= currentMonthStart && tx.date <= end else { continue }
            guard tx.kind == .standard else { continue }
            guard tx.account?.isTrackingOnly != true else { continue }

            standardCount += 1
            if tx.amount > 0, tx.category?.group?.type == .income {
                income += tx.amount
            } else if tx.amount < 0 {
                spending += abs(tx.amount)
            }
        }

        derivedCashflow = .init(income: income, spending: spending)
        derivedStandardCount = standardCount
        derivedInferredMonthlySpending = standardCount > 0 ? (spending / Decimal(windowMonths)) : nil

        let transferPairs = Dictionary(grouping: transactions.compactMap { tx -> Transaction? in
            guard tx.date >= start && tx.date <= end else { return nil }
            guard tx.kind == .transfer else { return nil }
            guard tx.transferID != nil else { return nil }
            return tx
        }) { tx in
            tx.transferID ?? UUID()
        }

        var contributions: Decimal = 0

        for (_, legs) in transferPairs {
            guard legs.count >= 2 else { continue }
            let includedLegs = legs.filter { tx in
                guard let accountID = tx.account?.persistentModelID else { return false }
                return includedAccountIDs.contains(accountID)
            }

            guard let retirementLeg = includedLegs.first else { continue }
            guard retirementLeg.amount > 0 else { continue }

            let otherLeg = legs.first { $0.persistentModelID != retirementLeg.persistentModelID }
            let otherAccountID = otherLeg?.account?.persistentModelID
            let otherIsIncluded = otherAccountID.map { includedAccountIDs.contains($0) } ?? false
            guard !otherIsIncluded else { continue }

            contributions += retirementLeg.amount
        }

        for tx in transactions {
            guard tx.date >= start && tx.date <= end else { continue }
            guard tx.kind == .standard else { continue }
            guard tx.amount > 0 else { continue }
            guard let accountID = tx.account?.persistentModelID, includedAccountIDs.contains(accountID) else { continue }
            contributions += tx.amount
        }

        derivedInferredMonthlyContribution = contributions > 0 ? (contributions / Decimal(windowMonths)) : nil
    }

    private func inferConfiguredIfNeeded() {
        guard !isConfigured else { return }
        let defaults = UserDefaults.standard
        // Infer configuration only if the user has changed something away from defaults.
        // This avoids "Delete Plan" immediately being re-inferred as configured just because keys exist.

        func int(_ key: String) -> Int? { defaults.object(forKey: key) as? Int }
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
        func double(_ key: String) -> Double? { defaults.object(forKey: key) as? Double }
        func string(_ key: String) -> String? { defaults.object(forKey: key) as? String }

        let changed =
            (int("retirement.currentAge").map { $0 != 30 } ?? false) ||
            (int("retirement.targetAge").map { $0 != 65 } ?? false) ||
            (bool("retirement.includeInvestmentAccounts").map { $0 != true } ?? false) ||
            (bool("retirement.includeSavingsAccounts").map { $0 != false } ?? false) ||
            (bool("retirement.includeOtherPositiveAccounts").map { $0 != false } ?? false) ||
            (bool("retirement.useSpendingFromTransactions").map { $0 != true } ?? false) ||
            (!(string("retirement.spendingMonthlyOverride") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (bool("retirement.useInferredContributions").map { $0 != true } ?? false) ||
            (!(string("retirement.monthlyContributionOverride") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (!(string("retirement.externalAssets") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (!(string("retirement.otherIncomeMonthly") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (bool("retirement.useManualTarget").map { $0 != false } ?? false) ||
            (!(string("retirement.manualTarget") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (double("retirement.safeWithdrawalRate").map { abs($0 - 0.04) > 0.000_000_1 } ?? false) ||
            (double("retirement.realReturn").map { abs($0 - 0.05) > 0.000_000_1 } ?? false)

        if changed {
            isConfigured = true
        }
    }

    private struct RetirementProjectionBandPoint: Identifiable {
        let age: Int
        let low: Double
        let high: Double
        var id: Int { age }
    }

    private var projectionBandSeries: [RetirementProjectionBandPoint] {
        guard yearsToRetirement > 0 else {
            let v = currentPortfolio.doubleValue
            return [RetirementProjectionBandPoint(age: currentAge, low: v, high: v)]
        }

        let lowerAnnual = max(-0.95, activeRealReturn - 0.02)
        let upperAnnual = max(-0.95, activeRealReturn + 0.02)
        let lowerMonthly = pow(1 + lowerAnnual, 1.0 / 12.0) - 1.0
        let upperMonthly = pow(1 + upperAnnual, 1.0 / 12.0) - 1.0

        return (0...yearsToRetirement).map { yearOffset in
            let months = yearOffset * 12
            let low = RetirementMath.futureValue(
                presentValue: currentPortfolio.doubleValue,
                monthlyContribution: monthlyContribution.doubleValue,
                monthlyReturn: lowerMonthly,
                months: months
            )
            let high = RetirementMath.futureValue(
                presentValue: currentPortfolio.doubleValue,
                monthlyContribution: monthlyContribution.doubleValue,
                monthlyReturn: upperMonthly,
                months: months
            )
            return RetirementProjectionBandPoint(
                age: currentAge + yearOffset,
                low: min(low, high),
                high: max(low, high)
            )
        }
    }

    // MARK: - Formatting

    private func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ImportParser.parseAmount(trimmed)
    }

    private func plainAmountString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? ""
    }

    private func formatCurrency(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0...0)))
    }

    private func compactCurrency(_ value: Decimal) -> String {
        let currencySymbol: String = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.maximumFractionDigits = 0
            return formatter.currencySymbol ?? currencyCode
        }()

        let doubleValue = value.doubleValue
        let isNegative = doubleValue < 0
        let absolute = abs(doubleValue)

        let compact = absolute.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
        .replacingOccurrences(of: "K", with: "k")

        if isNegative {
            return "-\(currencySymbol)\(compact)"
        }
        return "\(currencySymbol)\(compact)"
    }
}

#Preview {
    RetirementView()
}

private struct RetirementPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("retirement.isConfigured") private var isConfigured = false

    @AppStorage("retirement.currentAge") private var currentAge: Int = 30
    @AppStorage("retirement.targetAge") private var targetAge: Int = 65
    @AppStorage("retirement.includeInvestmentAccounts") private var includeInvestmentAccounts = true
    @AppStorage("retirement.includeSavingsAccounts") private var includeSavingsAccounts = false
    @AppStorage("retirement.includeOtherPositiveAccounts") private var includeOtherPositiveAccounts = false

    @AppStorage("retirement.useSpendingFromTransactions") private var useSpendingFromTransactions = true
    @AppStorage("retirement.spendingMonthlyOverride") private var spendingMonthlyOverrideText = ""

    @AppStorage("retirement.useInferredContributions") private var useInferredContributions = true
    @AppStorage("retirement.monthlyContributionOverride") private var monthlyContributionOverrideText = ""

    @AppStorage("retirement.externalAssets") private var externalAssetsText = ""
    @AppStorage("retirement.otherIncomeMonthly") private var otherIncomeMonthlyText = ""

    @AppStorage("retirement.useManualTarget") private var useManualTarget = false
    @AppStorage("retirement.manualTarget") private var manualTargetText = ""

    @AppStorage("retirement.safeWithdrawalRate") private var safeWithdrawalRate = 0.04
    @AppStorage("retirement.realReturn") private var realReturn = 0.05

    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Ages") {
                Stepper {
                    HStack {
                        Text("Current age")
                        Spacer()
                        Text("\(currentAge)")
                            .appSecondaryBodyStrongText()
                    }
                } onIncrement: {
                    currentAge = min(currentAge + 1, 80)
                } onDecrement: {
                    currentAge = max(currentAge - 1, 18)
                }

                Stepper {
                    HStack {
                        Text("Retire at")
                        Spacer()
                        Text("\(targetAge)")
                            .appSecondaryBodyStrongText()
                    }
                } onIncrement: {
                    targetAge = min(targetAge + 1, 80)
                } onDecrement: {
                    targetAge = max(targetAge - 1, 18)
                }
            }

            Section("Accounts Included") {
                Toggle("Investment", isOn: $includeInvestmentAccounts)
                Toggle("Savings", isOn: $includeSavingsAccounts)
                Toggle("Other positive balances", isOn: $includeOtherPositiveAccounts)
            }

            Section("Spending Goal") {
                Picker("Spending goal", selection: Binding(
                    get: { useSpendingFromTransactions ? 0 : 1 },
                    set: { useSpendingFromTransactions = ($0 == 0) }
                )) {
                    Text("Auto").tag(0)
                    Text("Manual").tag(1)
                }
                .pickerStyle(.segmented)

                if !useSpendingFromTransactions {
                    TextField("Monthly spend", text: $spendingMonthlyOverrideText)
                        .keyboardType(.decimalPad)
                }
            }

            Section("Contributions") {
                Picker("Contribution goal", selection: Binding(
                    get: { useInferredContributions ? 0 : 1 },
                    set: { useInferredContributions = ($0 == 0) }
                )) {
                    Text("Auto").tag(0)
                    Text("Manual").tag(1)
                }
                .pickerStyle(.segmented)

                if !useInferredContributions {
                    TextField("Monthly contribution", text: $monthlyContributionOverrideText)
                        .keyboardType(.decimalPad)
                }
            }

            Section {
                Toggle("Advanced assumptions", isOn: $showAdvanced)
            }

            if showAdvanced {
                Section("Assumptions") {
                    HStack {
                        Text("Safe withdrawal rate")
                        Spacer()
                        Text("\(String(format: "%.1f", safeWithdrawalRate * 100))%")
                            .appSecondaryBodyStrongText()
                    }
                    Slider(value: $safeWithdrawalRate, in: 0.025...0.05, step: 0.001)

                    HStack {
                        Text("Real return (after inflation)")
                        Spacer()
                        Text("\(Int(realReturn * 100))%")
                            .appSecondaryBodyStrongText()
                    }
                    Slider(value: $realReturn, in: 0.00...0.08, step: 0.0025)

                    Toggle("Set my own target", isOn: $useManualTarget)
                    if useManualTarget {
                        TextField("Target portfolio", text: $manualTargetText)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Other income at retirement (monthly)", text: $otherIncomeMonthlyText)
                        .keyboardType(.decimalPad)

                    TextField("External retirement assets", text: $externalAssetsText)
                        .keyboardType(.decimalPad)
                }
            }
        }
        .navigationTitle("Retirement Plan")
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    isConfigured = true
                    dismiss()
                }
            }
        }
    }
}

private struct RetirementProjectionPoint: Identifiable {
    let age: Int
    let value: Double
    var id: Int { age }
}

enum RetirementMath {
    static func futureValue(
        presentValue: Double,
        monthlyContribution: Double,
        monthlyReturn: Double,
        months: Int
    ) -> Double {
        guard months > 0 else { return presentValue }
        guard monthlyReturn.isFinite else { return presentValue }

        let r = monthlyReturn
        let n = Double(months)

        if abs(r) < 1e-9 {
            return presentValue + monthlyContribution * n
        }

        let growth = pow(1 + r, n)
        let futureValueOfPresent = presentValue * growth
        let futureValueOfContributions = monthlyContribution * ((growth - 1) / r)
        return futureValueOfPresent + futureValueOfContributions
    }

    static func requiredMonthlyContribution(
        presentValue: Double,
        targetValue: Double,
        monthlyReturn: Double,
        months: Int
    ) -> Double {
        guard months > 0 else { return presentValue >= targetValue ? 0 : .infinity }
        guard targetValue > 0 else { return 0 }

        let r = monthlyReturn
        let n = Double(months)
        let growth = abs(r) < 1e-9 ? 1 : pow(1 + r, n)
        let futureValueOfPresent = presentValue * growth
        let needed = targetValue - futureValueOfPresent
        guard needed > 0 else { return 0 }

        if abs(r) < 1e-9 {
            return needed / n
        }

        let annuityFactor = (growth - 1) / r
        guard annuityFactor > 0 else { return .infinity }
        return needed / annuityFactor
    }

    static func monthsToReachTarget(
        presentValue: Double,
        monthlyContribution: Double,
        monthlyReturn: Double,
        targetValue: Double,
        maxMonths: Int
    ) -> Int? {
        guard targetValue > 0 else { return 0 }
        guard maxMonths > 0 else { return nil }
        guard presentValue.isFinite else { return nil }

        if presentValue >= targetValue { return 0 }

        var balance = presentValue
        let r = monthlyReturn

        for month in 1...maxMonths {
            balance *= (1 + r)
            balance += monthlyContribution
            if balance >= targetValue {
                return month
            }
            if balance.isNaN || balance.isInfinite {
                return nil
            }
        }

        return nil
    }
}

private struct RetirementCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .appCardSurface()
    }
}

private struct RetirementRingProgress: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(max(0, min(1, progress)) * 100))%")
                .appCaptionText()
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 62, height: 62)
        .accessibilityLabel("Progress \(Int(max(0, min(1, progress)) * 100)) percent")
    }
}

private struct RetirementMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

	    var body: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	            Text(title)
	                .appCaptionText()
	                .foregroundStyle(.secondary)
	            Text(value)
	                .appSectionTitleText()
	                .fontWeight(.semibold)
	                .foregroundStyle(.primary)
	                .lineLimit(1)
	                .minimumScaleFactor(0.75)

            Text(subtitle)
                .appCaption2Text()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppDesign.Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct RetirementInlineMessage: View {
    let icon: String
    let tint: Color
    let text: String

	    var body: some View {
	        HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.small) {
	            Image(systemName: icon)
	                .foregroundStyle(tint)
	                .appCaptionText()
	                .padding(.top, AppDesign.Theme.Spacing.pixel)

	            Text(text)
	                .appSecondaryBodyText()
	                .foregroundStyle(.primary)

	            Spacer(minLength: 0)
	        }
	        .padding(AppDesign.Theme.Spacing.small)
	        .background(
	            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
	                .fill(Color(.systemBackground))
	        )
	        .overlay(
	            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
	                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
	        )
	    }
	}

private struct RetirementPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

	    var body: some View {
	        HStack(spacing: AppDesign.Theme.Spacing.small) {
	            Image(systemName: icon)
	                .foregroundStyle(tint)
	                .appSectionTitleText()

	            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
	                Text(title)
	                    .appCaptionText()
	                    .foregroundStyle(.secondary)
	                Text(value)
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
	                    .foregroundStyle(.primary)
	            }

            Spacer(minLength: 0)
        }
        .padding(AppDesign.Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct RetirementActionCard: View {
    let title: String
    let subtitle: String
    let detail: String?
    let tint: Color
    let primaryButtonTitle: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
		            HStack(spacing: AppDesign.Theme.Spacing.small) {
		                ZStack {
		                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
		                        .fill(tint.opacity(0.12))
		                    Image(systemName: "bolt.fill")
		                        .foregroundStyle(tint)
		                        .appSectionTitleText()
	                }
	                .frame(width: 36, height: 36)

	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
	                    Text(title)
	                        .appSecondaryBodyText()
	                        .fontWeight(.semibold)
	                    Text(subtitle)
	                        .appCaptionText()
	                        .foregroundStyle(.secondary)
	                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let detail {
                Text(detail)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Button(primaryButtonTitle) {
                primaryAction()
            }
            .appPrimaryCTA()
            .tint(tint)
        }
        .padding(AppDesign.Theme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RetirementKeyValueRow: View {
    let title: String
    let value: String

	    var body: some View {
	        HStack {
	            Text(title)
	                .foregroundStyle(.secondary)
            Spacer()
	            Text(value)
	                .foregroundStyle(.primary)
	        }
	        .font(AppDesign.Theme.Typography.secondaryBody)
	    }
	}

private struct RetirementAccountsDetailView: View {
    let accounts: [Account]
    let currencyCode: String
    let includeInvestmentAccounts: Bool
    let includeSavingsAccounts: Bool
    let includeOtherPositiveAccounts: Bool
    let externalAssets: Decimal

    @Environment(\.appColorMode) private var appColorMode

    private var includedAccounts: [Account] {
        accounts.filter { account in
            if account.balance <= 0 { return false }
            switch account.type {
            case .investment:
                return includeInvestmentAccounts
            case .savings:
                return includeSavingsAccounts
            case .chequing, .creditCard, .lineOfCredit, .mortgage, .loans, .other:
                return includeOtherPositiveAccounts
            }
        }
    }

    private var total: Decimal {
        includedAccounts.reduce(0) { $0 + max(0, $1.balance) } + max(0, externalAssets)
    }

    var body: some View {
        List {
	            Section {
	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
	                    Text("Included Assets")
	                        .appSectionTitleText()
	                    Text(total, format: .currency(code: currencyCode))
                            .appTitle2BoldText()
	                        .monospacedDigit()

                    Text("These balances are used as your starting portfolio for projections.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppDesign.Theme.Spacing.micro)
            }

            Section("Accounts") {
                if includedAccounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts Included",
                        systemImage: "tray",
                        description: Text("Enable Investment/Savings accounts in settings, or add an external balance.")
                    )
                    .listRowSeparator(.hidden)
                } else {
	                    ForEach(includedAccounts) { account in
	                        HStack(spacing: AppDesign.Theme.Spacing.tight) {
                            ZStack {
                                Circle()
                                    .fill(account.type.color(for: appColorMode).opacity(0.18))
                                Image(systemName: account.type.icon)
                                    .foregroundStyle(account.type.color(for: appColorMode))
                                    .appDisplayText(AppDesign.Theme.DisplaySize.xSmall, weight: .semibold)
                            }
                            .frame(width: 30, height: 30)

	                            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
	                                Text(account.name)
	                                    .appSecondaryBodyText()
	                                    .fontWeight(.semibold)
	                                Text(account.type.rawValue)
	                                    .appCaptionText()
	                                    .foregroundStyle(.secondary)
	                            }

                            Spacer()

	                            Text(account.balance, format: .currency(code: currencyCode))
	                                .appSecondaryBodyText()
	                                .fontWeight(.semibold)
	                                .monospacedDigit()
	                        }
	                    }
	                }
            }

            if externalAssets > 0 {
                Section("External") {
                    HStack {
                        Text("External assets")
                        Spacer()
                        Text(externalAssets, format: .currency(code: currencyCode))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Included Assets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RetirementAssumptionsHelpView: View {
    let safeWithdrawalRate: Double
    let realReturn: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
	                Section("What these mean") {
	                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
	                        Text("Safe withdrawal rate (SWR)")
	                            .appSectionTitleText()
	                        Text("A common guideline is 4%, meaning a $1,000,000 portfolio could support about $40,000 per year (in today’s dollars), before taxes. Lower SWR is more conservative.")
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)

	                        Text("Real return")
	                            .appSectionTitleText()
	                            .padding(.top, AppDesign.Theme.Spacing.xSmall)
	                        Text("This is your expected investment return after inflation. Using a real return keeps everything in today’s dollars, making it easier to reason about your goal.")
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)
	                    }
	                    .padding(.vertical, AppDesign.Theme.Spacing.micro)
	                }

                Section("Current settings") {
                    LabeledContent("SWR", value: "\(String(format: "%.1f", safeWithdrawalRate * 100))%")
                    LabeledContent("Real return", value: "\(Int(realReturn * 100))%")
                }

                Section {
                    Text("This tool is for planning and education only. Consider taxes, fees, and real-life variability.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Assumptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Decimal {
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}
