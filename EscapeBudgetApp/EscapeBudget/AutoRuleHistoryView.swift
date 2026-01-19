import SwiftUI
import SwiftData

struct AutoRuleHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @Query(sort: \AutoRuleApplication.appliedAt, order: .reverse)
    private var applications: [AutoRuleApplication]

    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedFieldFilter: AutoRuleFieldChange?

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
            result = result.filter { $0.fieldChanged == fieldFilter.rawValue }
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
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date filter
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        label: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
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
                        label: field.rawValue,
                        icon: field.systemImage,
                        isSelected: selectedFieldFilter == field
                    ) {
                        selectedFieldFilter = field
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, AppTheme.Spacing.small)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            ForEach(groupedApplications, id: \.0) { group, apps in
                Section {
                    ForEach(apps) { app in
                        HistoryRowView(application: app, currencyCode: currencyCode)
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
	                    VStack(spacing: 12) {
	                        Image(systemName: "line.3.horizontal.decrease.circle")
	                            .font(.system(size: 32))
	                            .foregroundStyle(.secondary)
	                        Text("No matches for current filters")
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)
	                        Button("Clear Filters") {
	                            selectedFilter = .all
	                            selectedFieldFilter = nil
	                        }
	                        .font(AppTheme.Typography.secondaryBody)
	                    }
	                    .frame(maxWidth: .infinity)
	                    .padding(.vertical, AppTheme.Spacing.large)
	                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))

	            VStack(spacing: 8) {
	                Text("No History Yet")
	                    .font(.title2)
	                    .fontWeight(.semibold)

	                Text("When auto rules modify transactions during import, the changes will appear here.")
	                    .appSecondaryBodyText()
	                    .foregroundStyle(.secondary)
	                    .multilineTextAlignment(.center)
	                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
	            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .appCaptionText()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.tint(for: appColorMode) : Color(.tertiarySystemFill))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(AppTheme.Radius.card)
        }
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    let application: AutoRuleApplication
    let currencyCode: String
    @Environment(\.appColorMode) private var appColorMode

    private var fieldChange: AutoRuleFieldChange? {
        AutoRuleFieldChange(rawValue: application.fieldChanged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .foregroundColor(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .secondary)
                }
            }

            // Change details
            HStack(spacing: 8) {
                if let field = fieldChange {
                    Image(systemName: field.systemImage)
                        .appCaptionText()
                        .foregroundColor(AppColors.tint(for: appColorMode))
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let oldValue = application.oldValue, !oldValue.isEmpty {
                        HStack(spacing: 4) {
                            Text(oldValue)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
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
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.warning(for: appColorMode).opacity(0.2))
                        .foregroundColor(AppColors.warning(for: appColorMode))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
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
	        VStack(alignment: .leading, spacing: 12) {
	            Text("Statistics")
	                .appSectionTitleText()

            HStack(spacing: AppTheme.Spacing.medium) {
                StatBox(value: "\(totalChanges)", label: "Total Changes")

                ForEach(changesByField.prefix(3), id: \.0) { field, count in
                    StatBox(
                        value: "\(count)",
                        label: field.rawValue,
                        icon: field.systemImage
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(AppTheme.Radius.compact)
    }
}

struct StatBox: View {
    let value: String
    let label: String
    var icon: String? = nil
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        VStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .appCaptionText()
                    .foregroundColor(AppColors.tint(for: appColorMode))
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
