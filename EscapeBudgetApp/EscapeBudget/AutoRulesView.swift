import SwiftUI
import SwiftData

struct AutoRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \AutoRule.order) private var rules: [AutoRule]

    @State private var selectedTab: Tab = .rules
    @State private var showingRuleEditor = false
    @State private var ruleToEdit: AutoRule?
    @State private var ruleToApplyRetroactively: AutoRule?
    @State private var showingDeleteConfirmation = false
    @State private var ruleToDelete: AutoRule?

    enum Tab: String, CaseIterable {
        case rules = "Rules"
        case history = "History"

        var systemImage: String {
            switch self {
            case .rules: return "list.bullet.rectangle"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("View", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content
                switch selectedTab {
                case .rules:
                    rulesListView
                case .history:
                    AutoRuleHistoryView()
                }
            }
            .navigationTitle("Auto Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if selectedTab == .rules {
                        Button {
                            ruleToEdit = nil
                            showingRuleEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Rule")
                        .accessibilityIdentifier("autoRules.addRule")
                    }
                }
            }
            .sheet(isPresented: $showingRuleEditor) {
                AutoRuleEditorView(rule: ruleToEdit)
            }
            .sheet(item: $ruleToApplyRetroactively) { rule in
                NavigationStack {
                    ApplyRuleRetroactiveView(rule: rule)
                }
            }
            .confirmationDialog(
                "Delete Rule",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let rule = ruleToDelete {
                        deleteRule(rule)
                    }
                }
                Button("Cancel", role: .cancel) {
                    ruleToDelete = nil
                }
            } message: {
                if let rule = ruleToDelete {
                    Text("Are you sure you want to delete \"\(rule.name)\"? This cannot be undone.")
                }
            }
        }
    }

    // MARK: - Rules List View

    private var rulesListView: some View {
        Group {
            if rules.isEmpty {
                emptyStateView
            } else {
                List {
                    Section {
                        ForEach(rules) { rule in
                            RuleRowView(
                                rule: rule,
                                onTap: {
                                    ruleToEdit = rule
                                    showingRuleEditor = true
                                },
                                onToggle: { isEnabled in
                                    rule.isEnabled = isEnabled
                                    rule.updatedAt = Date()
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    ruleToApplyRetroactively = rule
                                } label: {
                                    Label("Apply Previous Transactions", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.teal)

                                Button(role: .destructive) {
                                    ruleToDelete = rule
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    duplicateRule(rule)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(AppColors.tint(for: appColorMode))

                                Button {
                                    ruleToApplyRetroactively = rule
                                } label: {
                                    Label("Apply Previous Transactions", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.teal)
                            }
                            .contextMenu {
                                Button {
                                    ruleToApplyRetroactively = rule
                                } label: {
                                    Label("Apply Previous Transactions", systemImage: "arrow.uturn.backward")
                                }

                                Button {
                                    duplicateRule(rule)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    ruleToDelete = rule
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: moveRules)
                    } header: {
                        HStack {
                            Text("\(rules.count) Rules")
                            Spacer()
                            Text("\(rules.filter(\.isEnabled).count) Active")
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Rules are applied in order from top to bottom during import. Drag to reorder.")
                            .appCaptionText()
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .appIconHero()
                .foregroundStyle(AppColors.tint(for: appColorMode).opacity(0.6))

            VStack(spacing: AppTheme.Spacing.compact) {
                Text("No Auto Rules Yet")
                    .appTitleText()
                    .fontWeight(.semibold)

                Text("Auto rules automatically rename, categorize, and tag your transactions during import.")
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
            }

            Button {
                ruleToEdit = nil
                showingRuleEditor = true
            } label: {
                Label("Create Your First Rule", systemImage: "plus.circle.fill")
            }
            .appPrimaryCTA()
            .controlSize(.large)

            Spacer()

            // Tips Section
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tight) {
                Text("What can Auto Rules do?")
                    .appSectionTitleText()

                TipRow(
                    icon: "person.text.rectangle",
                    title: "Auto Rename",
                    description: "Change \"AMZN*123ABC\" to \"Amazon\""
                )

                TipRow(
                    icon: "folder",
                    title: "Auto Categorize",
                    description: "Assign \"Groceries\" to Whole Foods transactions"
                )

                TipRow(
                    icon: "tag",
                    title: "Auto Tag",
                    description: "Add tags like \"Subscription\" or \"Work Expense\""
                )
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(AppTheme.Radius.small)
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Actions

    private func deleteRule(_ rule: AutoRule) {
        let service = AutoRulesService(modelContext: modelContext)
        service.deleteRule(rule)
        ruleToDelete = nil
    }

    private func duplicateRule(_ rule: AutoRule) {
        let service = AutoRulesService(modelContext: modelContext)
        let newRule = AutoRule(
            name: "\(rule.name) (Copy)",
            isEnabled: false,
            order: service.nextRuleOrder()
        )

        // Copy conditions
        newRule.matchPayeeCondition = rule.matchPayeeCondition
        newRule.matchPayeeValue = rule.matchPayeeValue
        newRule.matchPayeeCaseSensitive = rule.matchPayeeCaseSensitive
        newRule.matchAccount = rule.matchAccount
        newRule.matchAmountCondition = rule.matchAmountCondition
        newRule.matchAmountValue = rule.matchAmountValue
        newRule.matchAmountValueMax = rule.matchAmountValueMax

        // Copy actions
        newRule.actionRenamePayee = rule.actionRenamePayee
        newRule.actionCategory = rule.actionCategory
        newRule.actionTags = rule.actionTags
        newRule.actionMemo = rule.actionMemo
        newRule.actionAppendMemo = rule.actionAppendMemo
        newRule.actionStatus = rule.actionStatus

        modelContext.insert(newRule)
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var reorderedRules = rules
        reorderedRules.move(fromOffsets: source, toOffset: destination)

        let service = AutoRulesService(modelContext: modelContext)
        service.reorderRules(reorderedRules)
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    @Bindable var rule: AutoRule
    let onTap: () -> Void
    let onToggle: (Bool) -> Void
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(spacing: AppTheme.Spacing.tight) {
            // Enable Toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: AppColors.tint(for: appColorMode)))

            // Rule Info
            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                HStack {
                    Text(rule.name)
                        .font(AppTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)

	                    if rule.timesApplied > 0 {
	                        Text("\(rule.timesApplied)×")
	                            .font(.caption2)
	                            .padding(.horizontal, AppTheme.Spacing.xSmall)
	                            .padding(.vertical, AppTheme.Spacing.hairline)
	                            .background(AppColors.tint(for: appColorMode).opacity(0.1))
	                            .foregroundStyle(AppColors.tint(for: appColorMode))
	                            .cornerRadius(AppTheme.Radius.mini)
	                    }
	                }

                Text(rule.matchSummary)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Action icons
                HStack(spacing: AppTheme.Spacing.compact) {
                    if rule.actionRenamePayee != nil && !rule.actionRenamePayee!.isEmpty {
                        ActionBadge(icon: "person.text.rectangle", label: "Rename")
                    }
                    if rule.actionCategory != nil {
                        ActionBadge(icon: "folder", label: "Categorize")
                    }
                    if let tags = rule.actionTags, !tags.isEmpty {
                        ActionBadge(icon: "tag", label: "\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                    }
                    if rule.actionMemo != nil && !rule.actionMemo!.isEmpty {
                        ActionBadge(icon: "note.text", label: "Memo")
                    }
                    if rule.actionStatus != nil {
                        ActionBadge(icon: "checkmark.circle", label: "Status")
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.micro)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Action Badge

struct ActionBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.nano) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
	        .foregroundStyle(.secondary)
	        .padding(.horizontal, AppTheme.Spacing.xSmall)
	        .padding(.vertical, AppTheme.Spacing.hairline)
	        .background(Color(.tertiarySystemFill))
	        .cornerRadius(AppTheme.Radius.mini)
	    }
}

// MARK: - Tip Row

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.tight) {
            Image(systemName: icon)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppColors.tint(for: appColorMode))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                Text(title)
                    .appSecondaryBodyText()
                    .fontWeight(.medium)
                Text(description)
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
