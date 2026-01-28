import SwiftUI
import SwiftData
import Charts

struct BudgetPerformanceView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Query private var categoryGroups: [CategoryGroup]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode

	@Binding var selectedDate: Date
	@Binding var filterMode: DateRangeFilterHeader.FilterMode
	@Binding var customStartDate: Date
	@Binding var customEndDate: Date
    private let topChrome: AnyView?
	@State private var selectedCategory: Category?
    @State private var categoryToFix: Category?
    @State private var standardTransactions: [Transaction] = []
    @State private var netByCategoryID: [PersistentIdentifier: Decimal] = [:]
    @State private var transactionsByCategoryID: [PersistentIdentifier: [Transaction]] = [:]

    private var cacheTaskID: BudgetPerformanceCacheTaskID {
        BudgetPerformanceCacheTaskID(
            transactionsCount: standardTransactions.count,
            dataChangeToken: DataChangeTracker.token,
            start: dateRangeDates.0,
            end: dateRangeDates.1
        )
    }

    init(
        selectedDate: Binding<Date>,
        filterMode: Binding<DateRangeFilterHeader.FilterMode>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        topChrome: (() -> AnyView)? = nil
    ) {
        self._selectedDate = selectedDate
        self._filterMode = filterMode
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self.topChrome = topChrome?()
    }

    private var expenseGroups: [CategoryGroup] {
        categoryGroups.filter { $0.type == .expense }
    }
    
    private var dateRangeDates: (Date, Date) {
        let calendar = Calendar.current
        switch filterMode {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: selectedDate)) ?? selectedDate
            let end = calendar.date(byAdding: .year, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
            return (start, end)
        case .last3Months:
            let end = Date()
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? end
            return (start, end)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))?.addingTimeInterval(-1) ?? customEndDate
            return (start, end)
        }
    }
    
    private func activityFor(category: Category) -> Decimal {
        let net = netByCategoryID[category.persistentModelID] ?? 0
        return max(Decimal.zero, -net)
    }

    private func transactionsFor(category: Category) -> [Transaction] {
        transactionsByCategoryID[category.persistentModelID] ?? []
    }

    private func recomputeCategoryCaches() {
        var netTotals: [PersistentIdentifier: Decimal] = [:]
        var transactionsByCategory: [PersistentIdentifier: [Transaction]] = [:]

        for transaction in standardTransactions {
            guard transaction.account?.isTrackingOnly != true else { continue }
            guard let category = transaction.category else { continue }
            let categoryID = category.persistentModelID
            netTotals[categoryID, default: 0] += transaction.amount
            transactionsByCategory[categoryID, default: []].append(transaction)
        }

        netByCategoryID = netTotals
        transactionsByCategoryID = transactionsByCategory
    }
    
    private func groupActivity(_ group: CategoryGroup) -> Decimal {
        group.sortedCategories.reduce(0) { $0 + activityFor(category: $1) }
    }
    
    private func groupAssigned(_ group: CategoryGroup) -> Decimal {
        group.sortedCategories.reduce(0) { $0 + $1.assigned }
    }

    private var totalAssigned: Decimal {
        expenseGroups.reduce(0) { $0 + groupAssigned($1) }
    }

    private var totalSpent: Decimal {
        expenseGroups.reduce(0) { $0 + groupActivity($1) }
    }

    private var totalRemaining: Decimal {
        totalAssigned - totalSpent
    }

    private var daysProgress: (totalDays: Int, daysElapsed: Int, daysRemaining: Int)? {
        let start = dateRangeDates.0
        let end = dateRangeDates.1

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= startDay else { return nil }

        let totalDays = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let clampedNow = min(max(Date(), start), end)
        let elapsed = (calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: clampedNow)).day ?? 0) + 1
        let daysElapsed = max(1, min(totalDays, elapsed))
        let remaining = max(0, totalDays - daysElapsed)
        return (totalDays, daysElapsed, remaining)
    }

    private var projectedTotalSpent: Decimal? {
        guard let progress = daysProgress else { return nil }
        guard progress.daysElapsed > 0 else { return nil }
        let daily = totalSpent / Decimal(progress.daysElapsed)
        return daily * Decimal(progress.totalDays)
    }

    private var budgetCallouts: [ReviewCalloutBar.Item] {
        var items: [ReviewCalloutBar.Item] = []
        items.reserveCapacity(4)

        if let topOverBudgetCategory {
            items.append(
                ReviewCalloutBar.Item(
                    id: "top_over_budget",
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Top over budget",
                    value: "\(topOverBudgetCategory.category.name) • \(topOverBudgetCategory.overBy.formatted(.currency(code: currencyCode)))",
                    tint: AppColors.danger(for: appColorMode),
                    action: { categoryToFix = topOverBudgetCategory.category }
                )
            )
        }

        if let biggestLeftCategory {
            items.append(
                ReviewCalloutBar.Item(
                    id: "most_left",
                    systemImage: "chart.pie.fill",
                    title: "Most left",
                    value: "\(biggestLeftCategory.category.name) • \(biggestLeftCategory.left.formatted(.currency(code: currencyCode)))",
                    tint: AppColors.success(for: appColorMode),
                    action: { categoryToFix = biggestLeftCategory.category }
                )
            )
        }

        if let projectedTotalSpent, totalAssigned > 0 {
            let delta = projectedTotalSpent - totalAssigned
            items.append(
                ReviewCalloutBar.Item(
                    id: "projection",
                    systemImage: delta > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                    title: "Projection",
                    value: (delta > 0)
                        ? "Over by \(delta.formatted(.currency(code: currencyCode)))"
                        : "Left \(abs(delta).formatted(.currency(code: currencyCode)))",
                    tint: delta > 0 ? AppColors.warning(for: appColorMode) : AppColors.success(for: appColorMode),
                    action: nil
                )
            )
        }

        return items
    }

    private var overBudgetCategories: [(category: Category, overBy: Decimal, utilization: Double)] {
        var items: [(category: Category, overBy: Decimal, utilization: Double)] = []
        for group in expenseGroups {
            for category in group.sortedCategories {
                let assigned = max(0, category.assigned)
                guard assigned > 0 else { continue }
                let spent = activityFor(category: category)
                let over = spent - assigned
                if over > 0 {
                    let util = Double(truncating: (spent / assigned) as NSNumber)
                    items.append((category: category, overBy: over, utilization: util))
                }
            }
        }
        return items.sorted { a, b in
            if a.overBy != b.overBy { return a.overBy > b.overBy }
            return a.category.name < b.category.name
        }
    }

    private var topOverBudgetCategory: (category: Category, overBy: Decimal)? {
        overBudgetCategories.first.map { ($0.category, $0.overBy) }
    }

    private var biggestLeftCategory: (category: Category, left: Decimal)? {
        var best: (Category, Decimal)? = nil
        for group in expenseGroups {
            for category in group.sortedCategories {
                let assigned = max(0, category.assigned)
                guard assigned > 0 else { continue }
                let left = assigned - activityFor(category: category)
                guard left > 0 else { continue }
                if best == nil || left > (best?.1 ?? 0) {
                    best = (category, left)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    private var budgetPeriodLabel: String {
        let formatter = DateFormatter()
        switch filterMode {
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        case .last3Months:
            return "Last 3 Months"
        case .year:
            return selectedDate.formatted(.dateTime.year())
        case .custom:
            formatter.dateStyle = .short
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
    }

    private var hasBudgetGroups: Bool {
        !expenseGroups.isEmpty
    }

    private var hasBudgetData: Bool {
        totalAssigned > 0 || totalSpent > 0
    }

    private var shouldShowBudgetDetails: Bool {
        hasBudgetGroups && hasBudgetData
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.cardGap) {
                ScrollOffsetReader(coordinateSpace: "BudgetPerformanceView.scroll", id: "BudgetPerformanceView.scroll")
                if let topChrome {
                    topChrome
                }

                VStack(spacing: AppTheme.Spacing.cardGap) {
                    BudgetReviewSectionCard {
                        BudgetReviewSummaryCard(
                            currencyCode: currencyCode,
                            periodLabel: budgetPeriodLabel,
                            assigned: totalAssigned,
                            spent: totalSpent,
                            remaining: totalRemaining
                        )
                    }

                    if shouldShowBudgetDetails {
                        BudgetReviewSectionCard {
                            ReviewCalloutBar(title: "Quick Actions", items: budgetCallouts, isVertical: true)
                        }

                        ForEach(expenseGroups) { group in
                            let assigned = groupAssigned(group)
                            let spent = groupActivity(group)
                            let remaining = assigned - spent

                            BudgetReviewSectionCard {
                                BudgetReviewGroupCardHeader(
                                    groupName: group.name,
                                    assigned: assigned,
                                    spent: spent,
                                    remaining: remaining,
                                    currencyCode: currencyCode
                                )

                                VStack(spacing: 0) {
                                    ForEach(Array(group.sortedCategories.enumerated()), id: \.element.persistentModelID) { index, category in
                                        Button {
                                            selectedCategory = category
                                        } label: {
                                            BudgetProgressRow(
                                                category: category,
                                                activity: activityFor(category: category),
                                                transactionCount: transactionsFor(category: category).count
                                            )
                                            .padding(.vertical, AppTheme.Spacing.hairline)
                                        }
                                        .buttonStyle(.plain)

                                        if index != group.sortedCategories.count - 1 {
                                            Divider()
                                                .padding(.leading, AppTheme.Spacing.indentXL)
                                                .opacity(0.35)
                                        }
                                    }
                                }
                                .padding(.top, AppTheme.Spacing.compact)
                            }
                        }
                    } else {
                        BudgetReviewSectionCard {
                            BudgetInsightsEmptyStateCard(hasBudgetGroups: hasBudgetGroups)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.tight)
            }
        }
        .coordinateSpace(name: "BudgetPerformanceView.scroll")
        .background(BudgetPerformanceTransactionsQuery(start: dateRangeDates.0, end: dateRangeDates.1) { fetched in
            standardTransactions = fetched
        })
        .task(id: cacheTaskID) {
            recomputeCategoryCaches()
        }
        .sheet(item: $selectedCategory) { category in
            CategoryTransactionsSheet(
                category: category,
                transactions: transactionsFor(category: category),
                dateRange: dateRangeDates
            )
        }
        .sheet(item: $categoryToFix) { category in
            BudgetCategoryFixSheet(
                category: category,
                spent: activityFor(category: category),
                currencyCode: currencyCode,
                dateRange: dateRangeDates,
                transactions: transactionsFor(category: category)
            )
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct BudgetPerformanceCacheTaskID: Equatable {
    var transactionsCount: Int
    var dataChangeToken: Int
    var start: Date
    var end: Date
}

private struct BudgetPerformanceQueryTaskID: Equatable {
    var transactionsCount: Int
    var dataChangeToken: Int
    var start: Date
    var end: Date
}

private struct BudgetPerformanceTransactionsQuery: View {
    @Query private var transactions: [Transaction]
    private let onUpdate: ([Transaction]) -> Void
    private let start: Date
    private let end: Date

    init(start: Date, end: Date, onUpdate: @escaping ([Transaction]) -> Void) {
        self.start = start
        self.end = end
        self.onUpdate = onUpdate
        let kind = TransactionKind.standard.rawValue
        _transactions = Query(
            filter: #Predicate<Transaction> { tx in
                tx.date >= start &&
                tx.date <= end &&
                tx.kindRawValue == kind
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    var body: some View {
        Color.clear
            .task(id: BudgetPerformanceQueryTaskID(
                transactionsCount: transactions.count,
                dataChangeToken: DataChangeTracker.token,
                start: start,
                end: end
            )) {
                onUpdate(transactions)
            }
    }
}


private struct BudgetInsightsEmptyStateCard: View {
    let hasBudgetGroups: Bool

    var body: some View {
        ContentUnavailableView(
            hasBudgetGroups ? "No Budget Data Yet" : "No Budget Yet",
            systemImage: "sparkles",
            description: Text(
                hasBudgetGroups
                ? "Assign monthly amounts and add transactions to start seeing progress and insights."
                : "Add budget categories and assign monthly amounts to start tracking progress here."
            )
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.tight)
    }
}

struct BudgetReviewSectionCard<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .appCardSurface()
    }
}

private struct BudgetReviewSummaryCard: View {
    let currencyCode: String
    let periodLabel: String
    let assigned: Decimal
    let spent: Decimal
    let remaining: Decimal
    @Environment(\.appColorMode) private var appColorMode

    private var progress: Double {
        guard assigned > 0 else { return 0 }
        return min(1, Double(truncating: (spent / assigned) as NSNumber))
    }

    private var progressColor: Color {
        if assigned <= 0 { return AppColors.tint(for: appColorMode) }

        // Green up to 75%, orange 76-99%, red 100%+
        if progress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if progress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

	    var body: some View {
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.cardGap) {
	            HStack(alignment: .top, spacing: AppTheme.Spacing.tight) {
	                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                    Text("Budget Review")
	                        .appSectionTitleText()

	                    Text(periodLabel)
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                }

                Spacer()

                BudgetReviewRingProgress(progress: progress, color: progressColor)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small)
                ],
                spacing: AppTheme.Spacing.small
            ) {
                BudgetReviewMetricTile(
                    title: "Assigned",
                    value: assigned,
                    currencyCode: currencyCode,
                    valueColor: .primary
                )
                BudgetReviewMetricTile(
                    title: "Spent",
                    value: spent,
                    currencyCode: currencyCode,
                    valueColor: .secondary
                )
                BudgetReviewMetricTile(
                    title: "Left",
                    value: remaining,
                    currencyCode: currencyCode,
                    valueColor: remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode)
                )
            }
        }
    }
}

private struct BudgetReviewMetricTile: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)

            Text(value, format: .currency(code: currencyCode))
                .font(AppTheme.Typography.secondaryBody)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct BudgetReviewRingProgress: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .appCaptionText()
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 54, height: 54)
        .accessibilityLabel("Budget used \(Int(progress * 100)) percent")
    }
}

private struct BudgetReviewGroupCardHeader: View {
    let groupName: String
    let assigned: Decimal
    let spent: Decimal
    let remaining: Decimal
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    private var progress: Double {
        guard assigned > 0 else { return 0 }
        return min(1, Double(truncating: (spent / assigned) as NSNumber))
    }

    private var progressColor: Color {
        if assigned <= 0 { return AppColors.tint(for: appColorMode) }

        // Green up to 75%, orange 76-99%, red 100%+
        if progress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if progress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

	    private var spentPill: some View {
	        BudgetReviewMetricPill(
	            text: Text("Spent: \(spent.formatted(.currency(code: currencyCode)))"),
	            tint: .secondary
	        )
	    }

	    private var leftPill: some View {
	        BudgetReviewMetricPill(
	            text: Text("Left: \(remaining.formatted(.currency(code: currencyCode)))"),
	            tint: remaining >= 0 ? .secondary : AppColors.danger(for: appColorMode)
	        )
	    }

    private var pillsRow: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            spentPill
            leftPill
        }
    }

	    var body: some View {
	        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
	            Text(groupName)
	                .appSectionTitleText()
	                .lineLimit(1)
	                .minimumScaleFactor(0.8)

            ViewThatFits(in: .horizontal) {
                pillsRow

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    spentPill
                    leftPill
                }
            }

            ProgressView(value: progress)
                .tint(progressColor)
        }
    }
}

private struct BudgetReviewMetricPill: View {
    let text: Text
    let tint: Color

    var body: some View {
        text
            .appCaptionText()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .monospacedDigit()
            .padding(.vertical, AppTheme.Spacing.xSmall)
            .padding(.horizontal, AppTheme.Spacing.small)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
    }
}

struct BudgetProgressRow: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    let category: Category
    let activity: Decimal
    let transactionCount: Int
    
    private var isIncome: Bool {
        category.group?.type == .income
    }
    
    private var remaining: Decimal {
        category.assigned - activity
    }
    
    private var percentageRemaining: Double {
        guard category.assigned > 0 else { return activity > 0 ? 0 : 1 }
        return max(0, min(1, Double(truncating: remaining as NSNumber) / Double(truncating: category.assigned as NSNumber)))
    }
    
    private var percentageProgress: Double {
        guard category.assigned > 0 else { return activity > 0 ? 1 : 0 }
        return min(1, Double(truncating: activity as NSNumber) / Double(truncating: category.assigned as NSNumber))
    }
    
    private var progressColor: Color {
        if isIncome {
            return AppColors.tint(for: appColorMode)
        }

        // Green up to 75%, orange 76-99%, red 100%+
        if percentageProgress <= 0.75 {
            return AppColors.success(for: appColorMode)
        } else if percentageProgress < 1.0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.tight) {
            // Category icon
            Circle()
                .fill(progressColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(category.icon ?? String(category.name.prefix(1)).uppercased())
                        .font(.system(size: category.icon != nil ? 20 : 16, weight: .semibold))
                        .foregroundStyle(progressColor)
                )
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                HStack {
                    Text(category.name)
                        .font(AppTheme.Typography.body)
                        .fontWeight(.medium)
                    
                    if transactionCount > 0 {
                        Text("\(transactionCount)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, AppTheme.Spacing.hairline)
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .background(Capsule().fill(Color(.systemGray6)))
                    }
                    
                    Spacer()
                    
                    Text("\(Int(percentageProgress * 100))%")
                        .appCaptionText()
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                // Progress bar
	                GeometryReader { geometry in
	                    ZStack(alignment: .leading) {
	                        RoundedRectangle(cornerRadius: AppTheme.Radius.mini)
	                            .fill(Color(.systemGray5))
	                            .frame(height: 8)
	                        
	                        RoundedRectangle(cornerRadius: AppTheme.Radius.mini)
	                            .fill(progressColor.gradient)
	                            .frame(width: geometry.size.width * percentageProgress, height: 8)
	                    }
	                }
                .frame(height: 8)
                
                // Budget text
                HStack {
	                    if isIncome {
	                        Text(remaining >= 0 ? "\(remaining.formatted(.currency(code: currencyCode))) to go" : "\(abs(remaining).formatted(.currency(code: currencyCode))) over goal")
	                            .appCaptionText()
	                            .foregroundStyle(progressColor)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                        
	                        Spacer()
	                        
	                        Text("\(activity.formatted(.currency(code: currencyCode))) received")
	                            .appCaptionText()
	                            .foregroundStyle(.secondary)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                    } else {
	                        Text(remaining >= 0 ? "\(remaining.formatted(.currency(code: currencyCode))) remaining" : "\(abs(remaining).formatted(.currency(code: currencyCode))) over budget")
	                            .appCaptionText()
	                            .foregroundStyle(progressColor)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                        
	                        Spacer()
	                        
	                        Text("\(activity.formatted(.currency(code: currencyCode))) of \(category.assigned.formatted(.currency(code: currencyCode)))")
	                            .appCaptionText()
	                            .foregroundStyle(.secondary)
	                            .lineLimit(1)
	                            .minimumScaleFactor(0.5)
	                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.compact)
    }
}

#Preview {
    ReviewView()
}

// MARK: - Month Swipe Navigation Modifier
