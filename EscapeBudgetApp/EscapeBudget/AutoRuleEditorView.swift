import SwiftUI
import SwiftData

struct AutoRuleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \TransactionTag.order) private var tags: [TransactionTag]

    let rule: AutoRule?

    // Form State
    @State private var name: String = ""
    @State private var isEnabled: Bool = true

    // Match Conditions
    @State private var matchPayeeEnabled: Bool = false
    @State private var matchPayeeCondition: PayeeMatchCondition = .contains
    @State private var matchPayeeValue: String = ""
    @State private var matchPayeeCaseSensitive: Bool = false

    @State private var matchAccountEnabled: Bool = false
    @State private var matchAccount: Account?

    @State private var matchAmountEnabled: Bool = false
    @State private var matchAmountCondition: AmountMatchCondition = .any
    @State private var matchAmountValue: String = ""
    @State private var matchAmountValueMax: String = ""

    // Actions
    @State private var actionRenameEnabled: Bool = false
    @State private var actionRenamePayee: String = ""

    @State private var actionCategoryEnabled: Bool = false
    @State private var actionCategory: Category?

    @State private var actionTagsEnabled: Bool = false
    @State private var actionTags: Set<TransactionTag> = []

    @State private var actionMemoEnabled: Bool = false
    @State private var actionMemo: String = ""
    @State private var actionAppendMemo: Bool = false

    @State private var actionStatusEnabled: Bool = false
    @State private var actionStatus: TransactionStatus = .cleared

    // Preview
    @State private var showingPreview: Bool = false
    @State private var previewTransactions: [Transaction] = []
    @State private var showingRetroactiveApply: Bool = false

    private var isEditing: Bool { rule != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasConditions &&
        hasActions
    }

    private var hasConditions: Bool {
        (matchPayeeEnabled && !matchPayeeValue.isEmpty) ||
        matchAccountEnabled ||
        (matchAmountEnabled && matchAmountCondition != .any)
    }

    private var hasActions: Bool {
        (actionRenameEnabled && !actionRenamePayee.isEmpty) ||
        (actionCategoryEnabled && actionCategory != nil) ||
        (actionTagsEnabled && !actionTags.isEmpty) ||
        (actionMemoEnabled && !actionMemo.isEmpty) ||
        actionStatusEnabled
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section {
                    TextField("Rule Name", text: $name)
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Rule Info")
                } footer: {
                    Text("Give your rule a descriptive name like \"Rename Amazon\" or \"Categorize Groceries\".")
                }

                // Match Conditions
                Section {
                    // Payee Matching
                    DisclosureGroup(isExpanded: $matchPayeeEnabled) {
                        Picker("Condition", selection: $matchPayeeCondition) {
                            ForEach(PayeeMatchCondition.allCases) { condition in
                                Label(condition.rawValue, systemImage: condition.systemImage)
                                    .tag(condition)
                            }
                        }

                        TextField("Payee text to match", text: $matchPayeeValue)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Toggle("Case Sensitive", isOn: $matchPayeeCaseSensitive)
                    } label: {
                        ConditionToggleLabel(
                            icon: "person.text.rectangle",
                            title: "Match Payee",
                            isEnabled: matchPayeeEnabled,
                            summary: matchPayeeEnabled && !matchPayeeValue.isEmpty ?
                                "\(matchPayeeCondition.rawValue) \"\(matchPayeeValue)\"" : nil
                        )
                    }

                    // Account Matching
                    DisclosureGroup(isExpanded: $matchAccountEnabled) {
                        Picker("Account", selection: $matchAccount) {
                            Text("Select Account").tag(Optional<Account>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                    } label: {
                        ConditionToggleLabel(
                            icon: "building.columns",
                            title: "Match Account",
                            isEnabled: matchAccountEnabled,
                            summary: matchAccount?.name
                        )
                    }

                    // Amount Matching
                    DisclosureGroup(isExpanded: $matchAmountEnabled) {
                        Picker("Condition", selection: $matchAmountCondition) {
                            ForEach(AmountMatchCondition.allCases) { condition in
                                Text(condition.rawValue).tag(condition)
                            }
                        }

                        if matchAmountCondition != .any {
                            TextField("Amount", text: $matchAmountValue)
                                .keyboardType(.decimalPad)

                            if matchAmountCondition == .between {
                                TextField("Max Amount", text: $matchAmountValueMax)
                                    .keyboardType(.decimalPad)
                            }
                        }
                    } label: {
                        ConditionToggleLabel(
                            icon: "dollarsign.circle",
                            title: "Match Amount",
                            isEnabled: matchAmountEnabled && matchAmountCondition != .any,
                            summary: matchAmountEnabled && matchAmountCondition != .any ?
                                matchAmountCondition.rawValue : nil
                        )
                    }
                } header: {
                    Label("When Transaction Matches", systemImage: "magnifyingglass")
                } footer: {
                    if !hasConditions {
                        Text("Add at least one condition to match transactions.")
                            .foregroundColor(AppColors.warning(for: appColorMode))
                    }
                }

                // Actions
                Section {
                    // Rename Payee
                    DisclosureGroup(isExpanded: $actionRenameEnabled) {
                        TextField("New Payee Name", text: $actionRenamePayee)
                    } label: {
                        ActionToggleLabel(
                            icon: "person.text.rectangle",
                            title: "Rename Payee",
                            isEnabled: actionRenameEnabled,
                            summary: actionRenameEnabled && !actionRenamePayee.isEmpty ?
                                "→ \(actionRenamePayee)" : nil
                        )
                    }

                    // Set Category
                    DisclosureGroup(isExpanded: $actionCategoryEnabled) {
                        Picker("Category", selection: $actionCategory) {
                            Text("Select Category").tag(Optional<Category>.none)
                            ForEach(categories) { category in
                                HStack {
                                    if let group = category.group {
                                        Text("\(group.name) › \(category.name)")
                                    } else {
                                        Text(category.name)
                                    }
                                }
                                .tag(Optional(category))
                            }
                        }
                    } label: {
                        ActionToggleLabel(
                            icon: "folder",
                            title: "Set Category",
                            isEnabled: actionCategoryEnabled && actionCategory != nil,
                            summary: actionCategory?.name
                        )
                    }

                    // Add Tags
                    DisclosureGroup(isExpanded: $actionTagsEnabled) {
                        if tags.isEmpty {
                            Text("No tags available. Create tags first.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(tags) { tag in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: tag.colorHex) ?? .gray)
                                        .frame(width: 12, height: 12)
                                    Text(tag.name)
                                    Spacer()
                                    if actionTags.contains(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(AppColors.tint(for: appColorMode))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if actionTags.contains(tag) {
                                        actionTags.remove(tag)
                                    } else {
                                        actionTags.insert(tag)
                                    }
                                }
                            }
                        }
                    } label: {
                        ActionToggleLabel(
                            icon: "tag",
                            title: "Add Tags",
                            isEnabled: actionTagsEnabled && !actionTags.isEmpty,
                            summary: actionTags.isEmpty ? nil :
                                actionTags.map(\.name).sorted().joined(separator: ", ")
                        )
                    }

                    // Set Memo
                    DisclosureGroup(isExpanded: $actionMemoEnabled) {
                        TextField("Memo text", text: $actionMemo)
                        Toggle("Append to existing memo", isOn: $actionAppendMemo)
                    } label: {
                        ActionToggleLabel(
                            icon: "note.text",
                            title: "Set Memo",
                            isEnabled: actionMemoEnabled && !actionMemo.isEmpty,
                            summary: actionMemoEnabled && !actionMemo.isEmpty ?
                                (actionAppendMemo ? "Append" : "Set") : nil
                        )
                    }

                    // Set Status
                    DisclosureGroup(isExpanded: $actionStatusEnabled) {
                        Picker("Status", selection: $actionStatus) {
                            ForEach(TransactionStatus.allCases, id: \.self) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                    } label: {
                        ActionToggleLabel(
                            icon: "checkmark.circle",
                            title: "Set Status",
                            isEnabled: actionStatusEnabled,
                            summary: actionStatusEnabled ? actionStatus.rawValue : nil
                        )
                    }
                } header: {
                    Label("Then Apply These Actions", systemImage: "wand.and.stars")
                } footer: {
                    if !hasActions {
                        Text("Add at least one action to apply to matching transactions.")
                            .foregroundColor(AppColors.warning(for: appColorMode))
                    }
                }

                // Preview Section
                if hasConditions {
                    Section {
                        Button {
                            loadPreview()
                        } label: {
                            HStack {
                                Image(systemName: "eye")
                                Text("Preview Matching Transactions")
                                Spacer()
                                if !previewTransactions.isEmpty {
                                    Text("\(previewTransactions.count) matches")
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    } header: {
                        Text("Preview")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Rule" : "New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isEditing {
                        Button {
                            showingRetroactiveApply = true
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .accessibilityLabel("Apply Previous Transactions")
                    }

                    Button(isEditing ? "Save" : "Create") {
                        saveRule()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadRuleData()
            }
            .sheet(isPresented: $showingPreview) {
                PreviewMatchesSheet(transactions: previewTransactions)
            }
            .sheet(isPresented: $showingRetroactiveApply) {
                if let rule {
                    NavigationStack {
                        ApplyRuleRetroactiveView(rule: rule)
                    }
                }
            }
        }
    }

    // MARK: - Load/Save

    private func loadRuleData() {
        guard let rule = rule else { return }

        name = rule.name
        isEnabled = rule.isEnabled

        // Conditions
        if let condition = rule.matchPayeeCondition, let value = rule.matchPayeeValue {
            matchPayeeEnabled = true
            matchPayeeCondition = condition
            matchPayeeValue = value
            matchPayeeCaseSensitive = rule.matchPayeeCaseSensitive
        }

        if let account = rule.matchAccount {
            matchAccountEnabled = true
            matchAccount = account
        }

        if let condition = rule.matchAmountCondition, condition != .any {
            matchAmountEnabled = true
            matchAmountCondition = condition
            if let value = rule.matchAmountValue {
                matchAmountValue = "\(value)"
            }
            if let max = rule.matchAmountValueMax {
                matchAmountValueMax = "\(max)"
            }
        }

        // Actions
        if let payee = rule.actionRenamePayee, !payee.isEmpty {
            actionRenameEnabled = true
            actionRenamePayee = payee
        }

        if let category = rule.actionCategory {
            actionCategoryEnabled = true
            actionCategory = category
        }

        if let ruleTags = rule.actionTags, !ruleTags.isEmpty {
            actionTagsEnabled = true
            actionTags = Set(ruleTags)
        }

        if let memo = rule.actionMemo, !memo.isEmpty {
            actionMemoEnabled = true
            actionMemo = memo
            actionAppendMemo = rule.actionAppendMemo
        }

        if let status = rule.actionStatus {
            actionStatusEnabled = true
            actionStatus = status
        }
    }

    private func saveRule() {
        let targetRule: AutoRule

        if let existing = rule {
            targetRule = existing
            targetRule.updatedAt = Date()
        } else {
            let service = AutoRulesService(modelContext: modelContext)
            targetRule = AutoRule(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                isEnabled: isEnabled,
                order: service.nextRuleOrder()
            )
            modelContext.insert(targetRule)
        }

        targetRule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        targetRule.isEnabled = isEnabled

        // Save conditions
        if matchPayeeEnabled && !matchPayeeValue.isEmpty {
            targetRule.matchPayeeCondition = matchPayeeCondition
            targetRule.matchPayeeValue = matchPayeeValue
            targetRule.matchPayeeCaseSensitive = matchPayeeCaseSensitive
        } else {
            targetRule.matchPayeeCondition = nil
            targetRule.matchPayeeValue = nil
        }

        targetRule.matchAccount = matchAccountEnabled ? matchAccount : nil

        if matchAmountEnabled && matchAmountCondition != .any {
            targetRule.matchAmountCondition = matchAmountCondition
            targetRule.matchAmountValue = Decimal(string: matchAmountValue)
            targetRule.matchAmountValueMax = matchAmountCondition == .between ?
                Decimal(string: matchAmountValueMax) : nil
        } else {
            targetRule.matchAmountCondition = nil
            targetRule.matchAmountValue = nil
            targetRule.matchAmountValueMax = nil
        }

        // Save actions
        targetRule.actionRenamePayee = actionRenameEnabled ? actionRenamePayee : nil
        targetRule.actionCategory = actionCategoryEnabled ? actionCategory : nil
        targetRule.actionTags = actionTagsEnabled && !actionTags.isEmpty ? Array(actionTags) : nil
        targetRule.actionMemo = actionMemoEnabled ? actionMemo : nil
        targetRule.actionAppendMemo = actionAppendMemo
        targetRule.actionStatus = actionStatusEnabled ? actionStatus : nil

        let didSave = modelContext.safeSave(context: "AutoRuleEditorView.saveRule")
        if didSave {
            dismiss()
        }
    }

    private func loadPreview() {
        // Create a temporary rule for preview
        let tempRule = AutoRule(name: "Preview", isEnabled: true)

        if matchPayeeEnabled && !matchPayeeValue.isEmpty {
            tempRule.matchPayeeCondition = matchPayeeCondition
            tempRule.matchPayeeValue = matchPayeeValue
            tempRule.matchPayeeCaseSensitive = matchPayeeCaseSensitive
        }

        tempRule.matchAccount = matchAccountEnabled ? matchAccount : nil

        if matchAmountEnabled && matchAmountCondition != .any {
            tempRule.matchAmountCondition = matchAmountCondition
            tempRule.matchAmountValue = Decimal(string: matchAmountValue)
            tempRule.matchAmountValueMax = Decimal(string: matchAmountValueMax)
        }

        let service = AutoRulesService(modelContext: modelContext)
        previewTransactions = service.previewMatchingTransactions(for: tempRule, limit: 50)
        showingPreview = true
    }
}

// MARK: - Supporting Views

struct ConditionToggleLabel: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let summary: String?
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isEnabled ? AppColors.tint(for: appColorMode) : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if let summary = summary {
                    Text(summary)
                        .appCaptionText()
                        .foregroundColor(AppColors.tint(for: appColorMode))
                }
            }

            Spacer()

            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success(for: appColorMode))
                    .appCaptionText()
            }
        }
    }
}

struct ActionToggleLabel: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let summary: String?
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isEnabled ? AppColors.warning(for: appColorMode) : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if let summary = summary {
                    Text(summary)
                        .appCaptionText()
                        .foregroundColor(AppColors.warning(for: appColorMode))
                }
            }

            Spacer()

            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success(for: appColorMode))
                    .appCaptionText()
            }
        }
    }
}

struct PreviewMatchesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currencyCode") private var currencyCode = "USD"
    let transactions: [Transaction]
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Matching Transactions")
                            .appSectionTitleText()
                        Text("No existing transactions match these conditions.")
                            .appSecondaryBodyText()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(transactions) { tx in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tx.payee)
                                            .font(.body)
                                        HStack(spacing: 8) {
                                            Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            if let account = tx.account {
                                                Text("• \(account.name)")
                                            }
                                        }
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(tx.amount, format: .currency(code: currencyCode))
                                        .foregroundColor(tx.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                                }
                            }
                        } header: {
                            Text("\(transactions.count) Matching Transactions")
                        } footer: {
                            Text("These are existing transactions that would match your rule conditions.")
                        }
                    }
                }
            }
            .navigationTitle("Preview Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
