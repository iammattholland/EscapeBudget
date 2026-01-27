import SwiftUI
import SwiftData

struct SpendingChallengesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var challenges: [SpendingChallenge]
    @Query(filter: #Predicate<Transaction> { !$0.isDemoData }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query private var categories: [Category]

    @State private var selectedTab: ChallengeTab = .active
    @State private var showingNewChallenge = false
    @State private var challengeToStart: ChallengeType?
    @State private var showingCustomBuilder = false
    @Query private var categoryGroups: [CategoryGroup]

    enum ChallengeTab: String, CaseIterable {
        case active = "Active"
        case available = "Browse"
        case completed = "History"
    }

    private var activeChallenges: [SpendingChallenge] {
        challenges.filter { $0.status == .active && !$0.isExpired }
    }

    private var completedChallenges: [SpendingChallenge] {
        challenges.filter { $0.status == .completed || $0.status == .failed }
            .sorted { ($0.completedDate ?? $0.endDate) > ($1.completedDate ?? $1.endDate) }
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: AppTheme.Spacing.tight) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text("Spending Challenges")
                                .appSectionTitleText()
                            Text("Build better habits with verifiable goals")
                                .appSecondaryBodyText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stats row
                    HStack(spacing: AppTheme.Spacing.medium) {
                        StatPill(value: "\(activeChallenges.count)", label: "Active")
                        StatPill(value: "\(completedChallenges.filter { $0.status == .completed }.count)", label: "Completed")
                        StatPill(value: "\(currentStreak)", label: "Streak")
                    }
                }
                .padding(.vertical, AppTheme.Spacing.micro)
            }

            // Create Custom Challenge button
            Section {
                Button {
                    showingCustomBuilder = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.tight) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text("Create Custom Challenge")
                                .appSectionTitleText()
                                .foregroundStyle(.primary)
                            Text("Set your own spending limits and goals")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, AppTheme.Spacing.xSmall)
            }

            // Tab picker
            Section {
                Picker("View", selection: $selectedTab) {
                    ForEach(ChallengeTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // Content based on tab
            switch selectedTab {
            case .active:
                activeSection
            case .available:
                availableSection
            case .completed:
                completedSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $challengeToStart) { challengeType in
            StartChallengeSheet(
                challengeType: challengeType,
                categories: categories,
                onStart: { challenge in
                    modelContext.insert(challenge)
                    try? modelContext.save()
                    challengeToStart = nil
                    selectedTab = .active
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingCustomBuilder) {
            CustomChallengeBuilderSheet(
                categories: Array(categories),
                categoryGroups: Array(categoryGroups),
                onStart: { challenge in
                    modelContext.insert(challenge)
                    try? modelContext.save()
                    showingCustomBuilder = false
                    selectedTab = .active
                }
            )
            .presentationDetents([.large])
        }
        .onAppear {
            updateChallengeStatuses()
        }
    }

    // MARK: - Active Challenges Section

    @ViewBuilder
    private var activeSection: some View {
        if activeChallenges.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Active Challenges",
                    systemImage: "flag",
                    description: Text("Start a challenge from the Browse tab to begin building better spending habits.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section("In Progress") {
                ForEach(activeChallenges, id: \.id) { challenge in
                    ActiveChallengeRow(
                        challenge: challenge,
                        result: ChallengeVerificationService.verify(
                            challenge: challenge,
                            transactions: Array(transactions),
                            categories: Array(categories)
                        )
                    )
                }
                .onDelete(perform: deleteActiveChallenges)
            }
        }
    }

    // MARK: - Available Challenges Section

    @ViewBuilder
    private var availableSection: some View {
        Section("Easy") {
            ForEach(ChallengeType.presets.filter { $0.difficulty == .easy }) { type in
                AvailableChallengeRow(type: type) {
                    challengeToStart = type
                }
            }
        }

        Section("Medium") {
            ForEach(ChallengeType.presets.filter { $0.difficulty == .medium }) { type in
                AvailableChallengeRow(type: type) {
                    challengeToStart = type
                }
            }
        }

        Section("Hard") {
            ForEach(ChallengeType.presets.filter { $0.difficulty == .hard }) { type in
                AvailableChallengeRow(type: type) {
                    challengeToStart = type
                }
            }
        }
    }

    // MARK: - Completed Challenges Section

    @ViewBuilder
    private var completedSection: some View {
        if completedChallenges.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Completed Challenges",
                    systemImage: "trophy",
                    description: Text("Completed and failed challenges will appear here.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section("Past Challenges") {
                ForEach(completedChallenges, id: \.id) { challenge in
                    CompletedChallengeRow(challenge: challenge)
                }
                .onDelete(perform: deleteCompletedChallenges)
            }
        }
    }

    // MARK: - Helpers

    private var currentStreak: Int {
        completedChallenges
            .filter { $0.status == .completed }
            .prefix(10)
            .reduce(0) { count, challenge in
                // Count consecutive completions
                if challenge.status == .completed { return count + 1 }
                return count
            }
    }

    private func deleteActiveChallenges(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(activeChallenges[index])
        }
        try? modelContext.save()
    }

    private func deleteCompletedChallenges(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(completedChallenges[index])
        }
        try? modelContext.save()
    }

    private func updateChallengeStatuses() {
        for challenge in challenges where challenge.status == .active {
            if challenge.isExpired {
                let result = ChallengeVerificationService.verify(
                    challenge: challenge,
                    transactions: Array(transactions),
                    categories: Array(categories)
                )
                challenge.currentProgress = result.progress
                challenge.status = result.passed ? .completed : .failed
                challenge.completedDate = Date()
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.micro) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

private struct ActiveChallengeRow: View {
    let challenge: SpendingChallenge
    let result: ChallengeResult
    @Environment(\.appColorMode) private var appColorMode

    private var progressColor: Color {
        if result.passed {
            return AppColors.success(for: appColorMode)
        } else if result.progress > 0.5 {
            return AppColors.warning(for: appColorMode)
        } else if result.progress > 0 {
            return AppColors.warning(for: appColorMode)
        } else {
            return AppColors.danger(for: appColorMode)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: challenge.displayIcon)
                    .foregroundStyle(progressColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text(challenge.displayTitle)
                        .appSectionTitleText()
                    Text("\(challenge.daysRemaining) days remaining")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppTheme.Spacing.micro) {
                    Text("\(Int(result.progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(progressColor)
                    Text(result.message)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ProgressView(value: result.progress)
                .tint(progressColor)
        }
        .padding(.vertical, AppTheme.Spacing.xSmall)
    }
}

private struct AvailableChallengeRow: View {
    let type: ChallengeType
    let onStart: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    private var difficultyColor: Color {
        switch type.difficulty {
        case .easy: return AppColors.success(for: appColorMode)
        case .medium: return AppColors.warning(for: appColorMode)
        case .hard: return AppColors.danger(for: appColorMode)
        }
    }

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: AppTheme.Spacing.tight) {
                Image(systemName: type.icon)
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    HStack {
                        Text(type.title)
                            .appSectionTitleText()
                            .foregroundStyle(.primary)

                        Text(type.difficulty.rawValue)
                            .appCaptionText()
                            .fontWeight(.medium)
                            .foregroundStyle(difficultyColor)
                            .padding(.horizontal, AppTheme.Spacing.xSmall)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.mini, style: .continuous)
                                    .fill(difficultyColor.opacity(0.15))
                            )
                    }
                    Text(type.description)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppTheme.Spacing.xSmall)
    }
}

private struct CompletedChallengeRow: View {
    let challenge: SpendingChallenge
    @Environment(\.appColorMode) private var appColorMode

    private var statusColor: Color {
        challenge.status == .completed
            ? AppColors.success(for: appColorMode)
            : AppColors.danger(for: appColorMode)
    }

    private var statusIcon: String {
        challenge.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.tight) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                Text(challenge.displayTitle)
                    .appSectionTitleText()
                if let completedDate = challenge.completedDate {
                    Text(completedDate.formatted(date: .abbreviated, time: .omitted))
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(challenge.status == .completed ? "Passed" : "Failed")
                .appCaptionText()
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, AppTheme.Spacing.xSmall)
    }
}

// MARK: - Start Challenge Sheet

private struct StartChallengeSheet: View {
    let challengeType: ChallengeType
    let categories: [Category]
    let onStart: (SpendingChallenge) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var duration: Int
    @State private var targetAmount: String = ""
    @State private var selectedCategory: String = ""

    init(challengeType: ChallengeType, categories: [Category], onStart: @escaping (SpendingChallenge) -> Void) {
        self.challengeType = challengeType
        self.categories = categories
        self.onStart = onStart
        self._duration = State(initialValue: challengeType.defaultDurationDays)
    }

    private var needsTargetAmount: Bool {
        [.entertainmentDiet, .weeklySpendingLimit, .noImpulseBuys].contains(challengeType)
    }

    private var needsCategorySelection: Bool {
        challengeType == .categoryFreeze
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: challengeType.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text(challengeType.title)
                                .appSectionTitleText()
                            Text(challengeType.description)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                }

                Section("Duration") {
                    Stepper("\(duration) days", value: $duration, in: 1...90)
                }

                if needsTargetAmount {
                    Section("Target Amount") {
                        TextField("Amount", text: $targetAmount)
                            .keyboardType(.decimalPad)
                    }
                }

                if needsCategorySelection {
                    Section("Category to Freeze") {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Select category").tag("")
                            ForEach(categories.filter { $0.group?.type == .expense }, id: \.name) { category in
                                Text(category.name).tag(category.name)
                            }
                        }
                    }
                }

                Section {
                    Button(action: startChallenge) {
                        Text("Start Challenge")
                            .frame(maxWidth: .infinity)
                    }
                    .appPrimaryCTA()
                    .disabled(needsCategorySelection && selectedCategory.isEmpty)
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startChallenge() {
        let challenge = SpendingChallenge(
            type: challengeType,
            durationDays: duration,
            targetAmount: Decimal(string: targetAmount),
            targetCategoryName: needsCategorySelection ? selectedCategory : nil
        )
        onStart(challenge)
    }
}

// MARK: - Custom Challenge Builder Sheet

private struct CustomChallengeBuilderSheet: View {
    let categories: [Category]
    let categoryGroups: [CategoryGroup]
    let onStart: (SpendingChallenge) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    @State private var customTitle: String = ""
    @State private var selectedFilterType: CustomChallengeFilterType = .category
    @State private var selectedCategory: String = ""
    @State private var selectedCategoryGroup: String = ""
    @State private var payeeText: String = ""
    @State private var targetAmount: String = ""
    @State private var duration: Int = 7

    private var expenseCategories: [Category] {
        categories.filter { $0.group?.type == .expense }
    }

    private var expenseGroups: [CategoryGroup] {
        categoryGroups.filter { $0.type == .expense }
    }

    private var isValid: Bool {
        guard !targetAmount.isEmpty, Decimal(string: targetAmount) != nil else {
            return false
        }

        switch selectedFilterType {
        case .category:
            return !selectedCategory.isEmpty
        case .categoryGroup:
            return !selectedCategoryGroup.isEmpty
        case .payee:
            return !payeeText.isEmpty
        case .totalSpending:
            return true
        }
    }

    private var generatedTitle: String {
        if !customTitle.isEmpty { return customTitle }

        switch selectedFilterType {
        case .category:
            return selectedCategory.isEmpty ? "Category Limit" : "\(selectedCategory) Limit"
        case .categoryGroup:
            return selectedCategoryGroup.isEmpty ? "Group Limit" : "\(selectedCategoryGroup) Limit"
        case .payee:
            return payeeText.isEmpty ? "Payee Limit" : "\(payeeText) Limit"
        case .totalSpending:
            return "Spending Limit"
        }
    }

    var body: some View {
        NavigationStack {
            CustomChallengeForm(
                customTitle: $customTitle,
                selectedFilterType: $selectedFilterType,
                selectedCategory: $selectedCategory,
                selectedCategoryGroup: $selectedCategoryGroup,
                payeeText: $payeeText,
                targetAmount: $targetAmount,
                duration: $duration,
                expenseCategories: expenseCategories,
                expenseGroups: expenseGroups,
                isValid: isValid,
                generatedTitle: generatedTitle,
                filterValueSectionTitle: filterValueSectionTitle,
                startChallenge: startChallenge
            )
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filterValueSectionTitle: String {
        switch selectedFilterType {
        case .category: return "Select Category"
        case .categoryGroup: return "Select Budget Group"
        case .payee: return "Enter Merchant"
        case .totalSpending: return "Tracking"
        }
    }

    private func startChallenge() {
        guard let amount = Decimal(string: targetAmount) else { return }

        let filterValue: String
        switch selectedFilterType {
        case .category:
            filterValue = selectedCategory
        case .categoryGroup:
            filterValue = selectedCategoryGroup
        case .payee:
            filterValue = payeeText
        case .totalSpending:
            filterValue = "all"
        }

        let challenge = SpendingChallenge.createCustom(
            title: customTitle.isEmpty ? generatedTitle : customTitle,
            filterType: selectedFilterType,
            filterValue: filterValue,
            targetAmount: amount,
            durationDays: duration,
            categoryGroupName: selectedFilterType == .categoryGroup ? selectedCategoryGroup : nil
        )

        onStart(challenge)
    }
}

private struct CustomChallengeForm: View {
    @Binding var customTitle: String
    @Binding var selectedFilterType: CustomChallengeFilterType
    @Binding var selectedCategory: String
    @Binding var selectedCategoryGroup: String
    @Binding var payeeText: String
    @Binding var targetAmount: String
    @Binding var duration: Int
    let expenseCategories: [Category]
    let expenseGroups: [CategoryGroup]
    let isValid: Bool
    let generatedTitle: String
    let filterValueSectionTitle: String
    let startChallenge: () -> Void

    var body: some View {
        Form {
            headerSection
            filterTypeSection
            filterValueSection
            targetAmountSection
            durationSection
            customTitleSection
            startSection
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: AppTheme.Spacing.tight) {
                Image(systemName: "star.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("Custom Challenge")
                        .appSectionTitleText()
                    Text("Create your own spending goal")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }

    private var filterTypeSection: some View {
        Section("What to Limit") {
            ForEach(CustomChallengeFilterType.allCases) { filterType in
                Button {
                    selectedFilterType = filterType
                } label: {
                    HStack {
                        Image(systemName: filterType.icon)
                            .foregroundStyle(selectedFilterType == filterType ? Color.accentColor : Color.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(filterType.title)
                                .foregroundStyle(.primary)
                            Text(filterType.description)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedFilterType == filterType {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var filterValueSection: some View {
        Section(filterValueSectionTitle) {
            switch selectedFilterType {
            case .category:
                Picker("Category", selection: $selectedCategory) {
                    Text("Select a category").tag("")
                    ForEach(expenseCategories, id: \.name) { category in
                        Text(category.name).tag(category.name)
                    }
                }
                .pickerStyle(.menu)
            case .categoryGroup:
                Picker("Budget Group", selection: $selectedCategoryGroup) {
                    Text("Select a group").tag("")
                    ForEach(expenseGroups, id: \.name) { group in
                        Text(group.name).tag(group.name)
                    }
                }
                .pickerStyle(.menu)
            case .payee:
                TextField("Merchant name (e.g., Amazon, Starbucks)", text: $payeeText)
                    .textInputAutocapitalization(.words)
            case .totalSpending:
                Text("All discretionary spending will be tracked")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetAmountSection: some View {
        Section("Spending Limit") {
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Amount", text: $targetAmount)
                    .keyboardType(.decimalPad)
            }

            Text("Stay under this amount during the challenge period")
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            Stepper("\(duration) days", value: $duration, in: 1...90)

            HStack(spacing: AppTheme.Spacing.small) {
                DurationButton(label: "1 Week", days: 7, selected: duration == 7) { duration = 7 }
                DurationButton(label: "2 Weeks", days: 14, selected: duration == 14) { duration = 14 }
                DurationButton(label: "1 Month", days: 30, selected: duration == 30) { duration = 30 }
            }
        }
    }

    private var customTitleSection: some View {
        Section("Challenge Name (Optional)") {
            TextField("e.g., Coffee Budget, Amazon Fast", text: $customTitle)

            if customTitle.isEmpty {
                Text("Default: \(generatedTitle)")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startSection: some View {
        Section {
            Button(action: startChallenge) {
                Text("Start Challenge")
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryCTA()
            .disabled(!isValid)
        }
    }
}

private struct DurationButton: View {
    let label: String
    let days: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .appCaptionText()
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.tag, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                )
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        SpendingChallengesView()
    }
    .modelContainer(for: [SpendingChallenge.self, Transaction.self, Category.self], inMemory: true)
}
