import SwiftUI
import SwiftData

struct AutoRuleHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    
    @Query(sort: \AutoRuleApplication.appliedAt, order: .reverse)
    private var applications: [AutoRuleApplication]

    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedFieldFilter: AutoRuleFieldChange?
    @State private var showOverriddenOnly = false
    @State private var editingTransaction: Transaction?
    @State private var editingRule: AutoRule?

    enum HistoryFilter: String, CaseIterable {
        case all = "All"
        case recent = "Today"
        case week = "This Week"

        var predicate: Date? {
            let calendar = Calendar.current
            switch self {
            case .all: return nil
            case .recent: return calendar.startOfDay(for: Date())
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
            }
        }
    }

    private var filteredApplications: [AutoRuleApplication] {
        var result = applications

        // Filter by date
        if let minDate = selectedFilter.predicate {
            result = result.filter { $0.appliedAt >= minDate }
        }

        // Filter by field type
        if let fieldFilter = selectedFieldFilter {
            result = result.filter { AutoRuleFieldChange.fromStored($0.fieldChanged) == fieldFilter }
        }

        if showOverriddenOnly {
            result = result.filter(\.wasOverridden)
        }

        return result
    }

    private var groupedApplications: [(String, [AutoRuleApplication])] {
        let grouped = Dictionary(grouping: filteredApplications) { app -> String in
            let calendar = Calendar.current
            if calendar.isDateInToday(app.appliedAt) {
                return "Today"
            } else if calendar.isDateInYesterday(app.appliedAt) {
                return "Yesterday"
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()),
                      app.appliedAt >= weekAgo {
                return "This Week"
            } else {
                return app.appliedAt.formatted(.dateTime.month().year())
            }
        }

        // Sort groups by date (most recent first)
        let sortOrder = ["Today", "Yesterday", "This Week"]
        return grouped.sorted { first, second in
            let firstIndex = sortOrder.firstIndex(of: first.key) ?? Int.max
            let secondIndex = sortOrder.firstIndex(of: second.key) ?? Int.max
            if firstIndex != secondIndex {
                return firstIndex < secondIndex
            }
            // For month/year groups, sort by date of first item
            return (first.value.first?.appliedAt ?? .distantPast) >
                   (second.value.first?.appliedAt ?? .distantPast)
        }
    }

    var body: some View {
        Group {
            if applications.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    historyList
                }
            }
        }
        .sheet(item: $editingTransaction) { _ in
            transactionSheet
        }
        .sheet(item: $editingRule) { _ in
            ruleSheet
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppDesign.Theme.Spacing.compact) {
                // Date filter
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        label: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }

                FilterChip(
                    label: "Overridden",
                    icon: "arrow.uturn.backward.circle.fill",
                    isSelected: showOverriddenOnly
                ) {
                    showOverriddenOnly.toggle()
                }

                Divider()
                    .frame(height: 20)

                // Field type filter
                FilterChip(
                    label: "All Types",
                    isSelected: selectedFieldFilter == nil
                ) {
                    selectedFieldFilter = nil
                }

                ForEach(AutoRuleFieldChange.allCases, id: \.self) { field in
                    FilterChip(
                        label: field.displayName,
                        icon: field.systemImage,
                        isSelected: selectedFieldFilter == field
                    ) {
                        selectedFieldFilter = field
                    }
                }
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
            .padding(.vertical, AppDesign.Theme.Spacing.small)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            ForEach(groupedApplications, id: \.0) { group, apps in
                Section {
                    ForEach(apps) { app in
                        HistoryRowView(application: app, currencyCode: settings.currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let tx = app.transaction {
                                    editingTransaction = tx
                                } else if let rule = app.rule {
                                    editingRule = rule
                                }
                            }
                            .contextMenu {
                                if let tx = app.transaction {
                                    Button {
                                        editingTransaction = tx
                                    } label: {
                                        Label("Open Transaction", systemImage: "pencil.line")
                                    }
                                }

                                if let rule = app.rule {
                                    Button {
                                        editingRule = rule
                                    } label: {
                                        Label("Edit Rule", systemImage: "wand.and.stars")
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(group)
                        Spacer()
                        Text("\(apps.count) changes")
                            .foregroundStyle(.secondary)
                    }
                }
            }

	            if filteredApplications.isEmpty && !applications.isEmpty {
	                Section {
	                    VStack(spacing: AppDesign.Theme.Spacing.tight) {
	                        Image(systemName: "line.3.horizontal.decrease.circle")
	                            .appIconMedium()
	                            .foregroundStyle(.secondary)
	                        Text("No matches for current filters")
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)
	                        Button("Clear Filters") {
	                            selectedFilter = .all
	                            selectedFieldFilter = nil
                                showOverriddenOnly = false
	                        }
	                        .font(AppDesign.Theme.Typography.secondaryBody)
	                    }
	                    .frame(maxWidth: .infinity)
	                    .padding(.vertical, AppDesign.Theme.Spacing.large)
	                }
            }
        }
        .listStyle(.insetGrouped)
        .appListCompactSpacing()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        EmptyDataCard(
            systemImage: "clock.arrow.circlepath",
            title: "No History Yet",
            message: "When auto rules modify transactions during import, the changes will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

extension AutoRuleHistoryView {
    @ViewBuilder
    private var transactionSheet: some View {
        NavigationStack {
            if let editingTransaction {
                TransactionFormView(transaction: editingTransaction)
            }
        }
    }

    @ViewBuilder
    private var ruleSheet: some View {
        NavigationStack {
            if let editingRule {
                AutoRuleEditorView(rule: editingRule)
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppDesign.Theme.Spacing.micro) {
                if let icon = icon {
                    Image(systemName: icon)
                        .appCaption2Text()
                }
                Text(label)
                    .appCaptionText()
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.tight)
            .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
            .background(isSelected ? AppDesign.Colors.tint(for: appColorMode) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(AppDesign.Theme.Radius.card)
        }
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    let application: AutoRuleApplication
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    private var fieldChange: AutoRuleFieldChange? {
        AutoRuleFieldChange.fromStored(application.fieldChanged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
            // Header: Rule name and time
	            HStack {
	                if let rule = application.rule {
	                    Text(rule.name)
	                        .appSecondaryBodyText()
	                        .fontWeight(.medium)
	                } else {
	                    Text("Deleted Rule")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                        .italic()
	                }

                Spacer()

                Text(application.appliedAt.formatted(.dateTime.hour().minute()))
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            // Transaction info
            if let transaction = application.transaction {
                HStack {
                    Text(transaction.payee)
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(transaction.amount, format: .currency(code: currencyCode))
                        .appCaptionText()
                        .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .secondary)
                }
            }

            // Change details
            HStack(spacing: AppDesign.Theme.Spacing.compact) {
                if let field = fieldChange {
                    Image(systemName: field.systemImage)
                        .appCaptionText()
                        .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                }

                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                    if let oldValue = application.oldValue, !oldValue.isEmpty {
                        HStack(spacing: AppDesign.Theme.Spacing.micro) {
                            Text(oldValue)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .appCaption2Text()
                                .foregroundStyle(.secondary)
                            Text(application.newValue ?? "")
                                .foregroundStyle(.primary)
                        }
                        .appCaptionText()
                    } else {
                        Text("Set to: \(application.newValue ?? "")")
                            .appCaptionText()
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

	                if application.wasOverridden {
	                    Text("Overridden")
	                        .appCaption2Text()
	                        .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
	                        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
	                        .background(AppDesign.Colors.warning(for: appColorMode).opacity(0.2))
	                        .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
	                        .cornerRadius(AppDesign.Theme.Radius.mini)
	                }
	            }
	        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
    }
}

// MARK: - Stats View (Optional future enhancement)

struct AutoRuleStatsView: View {
    let applications: [AutoRuleApplication]

    private var totalChanges: Int { applications.count }

    private var changesByField: [(AutoRuleFieldChange, Int)] {
        let grouped = Dictionary(grouping: applications) { $0.fieldChanged }
        return AutoRuleFieldChange.allCases.compactMap { field in
            let count = grouped[field.rawValue]?.count ?? 0
            return count > 0 ? (field, count) : nil
        }.sorted { $0.1 > $1.1 }
    }

	    var body: some View {
	        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
	            Text("Statistics")
	                .appSectionTitleText()

            HStack(spacing: AppDesign.Theme.Spacing.medium) {
                StatBox(value: "\(totalChanges)", label: "Total Changes")

                ForEach(changesByField.prefix(3), id: \.0) { field, count in
                    StatBox(
                        value: "\(count)",
                        label: field.displayName,
                        icon: field.systemImage
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(AppDesign.Theme.Radius.compact)
    }
}

struct StatBox: View {
    let value: String
    let label: String
    var icon: String? = nil
    @Environment(\.appColorMode) private var appColorMode
    @Environment(\.appSettings) private var settings

    var body: some View {
        VStack(spacing: AppDesign.Theme.Spacing.micro) {
            if let icon = icon {
                Image(systemName: icon)
                    .appCaptionText()
                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
            }
            Text(value)
                .appTitleText()
                .fontWeight(.bold)
            Text(label)
                .appCaption2Text()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
