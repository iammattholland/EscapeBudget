import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    // MARK: - Category Mapping View
	    /// Categories from the import that haven't been mapped yet
	    var unmappedCategories: [String] {
	        importedCategories.filter { categoryMapping[$0] == nil }
	    }

	    // MARK: - Account Mapping View
	    var unmappedAccounts: [String] {
	        importedAccounts.filter { accountMapping[$0] == nil }
	    }

		    var accountMappingView: some View {
		        VStack {
		            Text("Map Accounts")
		                .appSectionTitleText()
		                .padding()

	            Text("Match account names from your file to accounts in Escape Budget.")
	                .appCaptionText()
	                .foregroundStyle(.secondary)

	            List {
	                Section {
	                    HStack {
	                        Label("\(importedAccounts.count - unmappedAccounts.count) mapped", systemImage: "checkmark.circle.fill")
	                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
	                        Spacer()
	                        Label("\(unmappedAccounts.count) unmapped", systemImage: "circle.dashed")
	                            .foregroundStyle(.secondary)
	                    }
	                    .appCaptionText()
	                } header: {
	                    Text("Status")
	                }

	                Section {
	                    ForEach(importedAccounts, id: \.self) { raw in
	                        HStack {
	                            Text(raw)
	                                .font(AppDesign.Theme.Typography.body)
	                            Spacer()

	                            Menu {
	                                Button("Create '\(raw)'...") {
	                                    startCreatingAccount(for: raw, prefill: true)
	                                }

	                                Button("Create New...") {
	                                    startCreatingAccount(for: raw, prefill: false)
	                                }

	                                Divider()

	                                ForEach(accounts) { account in
	                                    Button(account.name) {
	                                        accountMapping[raw] = account
	                                    }
	                                }

	                                Divider()

	                                Button("Use Default Account") {
	                                    accountMapping.removeValue(forKey: raw)
	                                }
	                            } label: {
	                                HStack {
	                                    if let mapped = accountMapping[raw] {
	                                        Text(mapped.name)
	                                            .foregroundStyle(.primary)
	                                        Image(systemName: "checkmark.circle.fill")
	                                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
	                                    } else {
	                                        Text("Use Default")
	                                            .foregroundStyle(.secondary)
	                                        Image(systemName: "chevron.up.chevron.down")
	                                            .appCaptionText()
	                                    }
	                                }
		                                .padding(.horizontal, AppDesign.Theme.Spacing.compact)
		                                .padding(.vertical, AppDesign.Theme.Spacing.micro)
		                                .background(Color(.secondarySystemBackground))
		                                .cornerRadius(AppDesign.Theme.Radius.xSmall)
		                            }
		                        }
		                    }
		                } header: {
	                    Text("Accounts")
	                } footer: {
	                    Text("Unmapped values will be assigned to your selected default account.")
	                }
	            }

	            Button("Next") {
	                prepareCategoryMapping()
	            }
	            .buttonStyle(.glass)
	            .controlSize(.large)
	            .padding()
	        }
	        .sheet(item: $accountCreationTarget) { target in
	            NavigationStack {
	                Form {
	                    Section {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	                            Text("Imported Value")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
		                            Text(target.rawAccount)
		                                .appSectionTitleText()
		                        }
		                    }

	                    Section("Details") {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
	                            Text("Name")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
	                            TextField("Enter account name", text: $newAccountName)
	                                .textInputAutocapitalization(.words)
	                        }

	                        Picker("Account Type", selection: $newAccountType) {
	                            ForEach(AccountType.allCases) { type in
	                                Text(type.rawValue).tag(type)
	                            }
	                        }

	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
	                            Text("Starting Balance")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
	                            HStack(spacing: AppDesign.Theme.Spacing.compact) {
	                                Text(currencySymbol(for: currencyCode))
	                                    .foregroundStyle(.secondary)
	                                TextField("0", text: $newAccountBalanceInput)
	                                    .keyboardType(.decimalPad)
	                            }
	                        }
	                    }
		            }
		            .navigationTitle("New Account")
		            .navigationBarTitleDisplayMode(.inline)
		            .globalKeyboardDoneToolbar()
		            .toolbar {
		                ToolbarItem(placement: .cancellationAction) {
		                    Button("Cancel") { accountCreationTarget = nil }
		                }
	                    ToolbarItem(placement: .confirmationAction) {
	                        Button("Add") {
	                            createAccountFromImportMapping(rawAccount: target.rawAccount)
	                        }
	                        .disabled(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	                    }
	                }
            }
            .presentationDetents([.large])
        }
    }

		    var categoryMappingView: some View {
		        VStack {
		            Text("Map Categories")
		                .appSectionTitleText()
	                .padding()

            Text("Match categories from your file to your Escape Budget categories.")
                .appCaptionText()
                .foregroundStyle(.secondary)

            List {
                // Bulk Actions Section
                if !unmappedCategories.isEmpty {
                    Section {
                        Button {
                            prepareBulkCategoryCreation()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                    Text("Create All Unmapped Categories")
                                        .font(AppDesign.Theme.Typography.body)
                                    Text("\(unmappedCategories.count) categories will be created")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    } header: {
                        Text("Quick Actions")
                    }
                }

                // Mapping Status Section
                Section {
                    HStack {
                        Label("\(importedCategories.count - unmappedCategories.count) mapped", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                        Spacer()
                        Label("\(unmappedCategories.count) unmapped", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    .appCaptionText()
                } header: {
                    Text("Status")
                }

                // Category List Section
                Section {
                    ForEach(importedCategories, id: \.self) { raw in
                        HStack {
                            Text(raw)
                                .font(AppDesign.Theme.Typography.body)
                            Spacer()

                            Menu {
                                Button("Create '\(raw)'...") {
                                    startCreatingCategory(for: raw, prefill: true)
                                }

                                Button("Create New...") {
                                    startCreatingCategory(for: raw, prefill: false)
                                }

                                Divider()

                                ForEach(allCategories) { cat in
                                    Button(cat.name) {
                                        categoryMapping[raw] = cat
                                    }
                                }

                                Button("None (Uncategorized)", role: .destructive) {
                                    categoryMapping[raw] = nil
                                }
                            } label: {
                                HStack {
                                    if let mapped = categoryMapping[raw] {
                                        Text(mapped.name)
                                            .foregroundStyle(.primary)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                                    } else {
                                        Text("Select Category")
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .appCaptionText()
                                    }
                                }
		                                .padding(.horizontal, AppDesign.Theme.Spacing.compact)
		                                .padding(.vertical, AppDesign.Theme.Spacing.micro)
		                                .background(Color(.secondarySystemBackground))
		                                .cornerRadius(AppDesign.Theme.Radius.xSmall)
		                            }
		                        }
		                    }
		                } header: {
                    Text("Categories")
                }
            }

            Button("Next") {
                prepareTagMappingOrReview()
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding()
        }
        .sheet(item: $categoryCreationTarget) { target in
            NavigationStack {
                Form {
	                    Section {
	                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	                            Text("Imported Value:")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
	                        }
	                    }
                    
                    Section("New Category Details") {
                        VStack(alignment: .leading) {
                            TextField("Category Name", text: $newCategoryName)
                            if newCategoryName != target.rawCategory {
                                Button("Use Imported Name") {
                                    newCategoryName = target.rawCategory
                                }
                                .appCaptionText()
                                .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                            }
                        }
                        
                        Toggle("Create New Group", isOn: $isCreatingNewGroup)
                        
                        if isCreatingNewGroup {
                            VStack(alignment: .leading) {
                                TextField("New Group Name", text: $newGroupNameRaw)
                                if newGroupNameRaw != target.rawCategory {
                                    Button("Use Imported Name") {
                                        newGroupNameRaw = target.rawCategory
                                    }
                                    .appCaptionText()
                                    .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                                }
                            }
                            Picker("Type", selection: $newGroupType) {
                                ForEach(CategoryGroupType.allCases.filter { $0 != .transfer }, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                        } else {
                            Picker("Group", selection: $newCategoryGroup) {
                                Text("Select Group").tag(Optional<CategoryGroup>.none)
                                ForEach(allGroups.filter { $0.type != .transfer }) { group in
                                    Text(group.name).tag(Optional(group))
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Create Category")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { categoryCreationTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createCategory(for: target.rawCategory)
                        }
                        .disabled(newCategoryName.isEmpty || (isCreatingNewGroup ? newGroupNameRaw.isEmpty : newCategoryGroup == nil))
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
        .sheet(isPresented: $showingBulkCategoryCreation) {
            NavigationStack {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                            Text("Create \(selectedUnmappedCategories.count) Categories")
                                .appSectionTitleText()
                            Text("These categories will be created and automatically mapped to your import data.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Grouping") {
                        Picker("Mode", selection: $bulkGroupingMode) {
                            ForEach(BulkGroupingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(bulkGroupingMode == .smart
                             ? "Smart grouping uses payee keywords and existing patterns to pick the best group. Unmatched categories default to Expenses."
                             : bulkGroupingMode == .single
                             ? "All categories will be created in a single group."
                             : "Assign categories to multiple groups before creating them.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(unmappedCategories, id: \.self) { raw in
                            HStack {
                                Image(systemName: selectedUnmappedCategories.contains(raw) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedUnmappedCategories.contains(raw) ? AppDesign.Colors.tint(for: appColorMode) : .gray)
                                Text(raw)
                                    .font(AppDesign.Theme.Typography.body)
                                Spacer()
                                if bulkGroupingMode != .single {
                                    Menu {
                                        ForEach(allGroups.filter { $0.type != .transfer }) { group in
                                            Button(group.name) {
                                                bulkCategoryAssignments[raw] = group
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: AppDesign.Theme.Spacing.micro) {
                                            Text(bulkCategoryAssignments[raw]?.name ?? "Assign Group")
                                                .foregroundStyle(.secondary)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .appCaptionText()
                                        }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedUnmappedCategories.contains(raw) {
                                    selectedUnmappedCategories.remove(raw)
                                } else {
                                    selectedUnmappedCategories.insert(raw)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Categories to Create")
                            Spacer()
                            if unmappedCategories.count > 1 {
                                Button {
                                    if selectedUnmappedCategories.count == unmappedCategories.count {
                                        selectedUnmappedCategories.removeAll()
                                    } else {
                                        selectedUnmappedCategories = Set(unmappedCategories)
                                    }
	                                } label: {
	                                    Text(selectedUnmappedCategories.count == unmappedCategories.count ? "Deselect All" : "Select All")
	                                        .appSecondaryBodyText()
	                                        .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
	                                }
                            }
                        }
                        .textCase(nil)
                    }

                    Section("Destination Group") {
                        if bulkGroupingMode == .single {
                            Toggle("Create New Group", isOn: $bulkCreateNewGroup)

                            if bulkCreateNewGroup {
                                TextField("Group Name", text: $bulkNewGroupName)
                                Picker("Type", selection: $bulkNewGroupType) {
                                    ForEach(CategoryGroupType.allCases.filter { $0 != .transfer }, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                            } else {
                                Picker("Group", selection: $bulkCategoryGroup) {
                                    Text("Select Group").tag(Optional<CategoryGroup>.none)
                                    ForEach(allGroups.filter { $0.type != .transfer }) { group in
                                        Text(group.name).tag(Optional(group))
                                    }
                                }
                            }
                        } else {
                            Text("Use Smart or Custom grouping to assign multiple groups.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if bulkGroupingMode != .single {
                        Section("Create Group") {
                            TextField("Group Name", text: $bulkNewGroupName)
                            Picker("Type", selection: $bulkNewGroupType) {
                                ForEach(CategoryGroupType.allCases.filter { $0 != .transfer }, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            Toggle("Assign to selected categories", isOn: $bulkAssignNewGroupToSelection)
                            Button("Add Group") {
                                createBulkGroupAndAssignIfNeeded()
                            }
                            .disabled(bulkNewGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if !bulkAssignmentSummary.isEmpty {
                        Section("Review") {
                            ForEach(bulkAssignmentSummary, id: \.groupID) { summary in
                                HStack {
                                    Text(summary.group.name)
                                    Spacer()
                                    Text("\(summary.count)")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Bulk Create")
                .navigationBarTitleDisplayMode(.inline)
                .globalKeyboardDoneToolbar()
                .onChange(of: bulkGroupingMode) { _, _ in
                    applyBulkGroupingMode()
                }
                .onChange(of: bulkCategoryGroup?.persistentModelID) { _, _ in
                    if bulkGroupingMode == .single, let group = bulkCategoryGroup {
                        assignAllSelected(to: group)
                    }
                }
                .onChange(of: selectedUnmappedCategories) { _, _ in
                    applyBulkGroupingMode()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingBulkCategoryCreation = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create \(selectedUnmappedCategories.count)") {
                            performBulkCategoryCreation()
                        }
                        .disabled(selectedUnmappedCategories.isEmpty || (bulkGroupingMode == .single && (bulkCreateNewGroup ? bulkNewGroupName.isEmpty : bulkCategoryGroup == nil)))
                    }
                }
            }
            .presentationDetents([.large])
            .solidPresentationBackground()
        }
    }

    func prepareBulkCategoryCreation() {
        // Pre-select all unmapped categories
        selectedUnmappedCategories = Set(unmappedCategories)
        let expensesGroup = getOrCreateDefaultExpensesGroup()
        bulkCategoryGroup = expensesGroup
        bulkCreateNewGroup = false
        bulkNewGroupName = ""
        bulkNewGroupType = .expense
        bulkGroupingMode = .smart
        bulkCategoryAssignments = [:]
        bulkCreatedGroups = []
        applyBulkGroupingMode()
        showingBulkCategoryCreation = true
    }

	    func performBulkCategoryCreation() {
        var createdGroup: CategoryGroup? = nil
        var createdCategories: [Category] = []

        if bulkGroupingMode == .single {
            if bulkCreateNewGroup {
                let newGroup = CategoryGroup(name: bulkNewGroupName, type: bulkNewGroupType)
                modelContext.insert(newGroup)
                allGroups.append(newGroup)
                bulkCategoryGroup = newGroup
                createdGroup = newGroup
            }
            guard let targetGroup = bulkCategoryGroup else { return }
            assignAllSelected(to: targetGroup)
        } else if bulkCategoryAssignments.isEmpty {
            applyBulkGroupingMode()
        }

        // Create all selected categories
        for rawCategory in selectedUnmappedCategories {
            let newCat = Category(name: rawCategory)
            let targetGroup = bulkCategoryAssignments[rawCategory] ?? getOrCreateDefaultExpensesGroup()
            newCat.group = targetGroup
            modelContext.insert(newCat)
            createdCategories.append(newCat)
            allCategories.append(newCat)
            categoryMapping[rawCategory] = newCat
        }

        // Save context
        guard modelContext.safeSave(context: "ImportDataView.performBulkCategoryCreation", showErrorToUser: false) else {
            if let createdGroup {
                allGroups.removeAll { $0.persistentModelID == createdGroup.persistentModelID }
                modelContext.delete(createdGroup)
            }
            for category in createdCategories {
                allCategories.removeAll { $0.persistentModelID == category.persistentModelID }
                modelContext.delete(category)
            }
            for rawCategory in selectedUnmappedCategories {
                categoryMapping[rawCategory] = nil
            }
            errorMessage = "Couldn’t create categories. Please try again."
            return
        }

        // Close sheet
        showingBulkCategoryCreation = false
    }

    private var bulkAssignmentSummary: [(group: CategoryGroup, count: Int, groupID: PersistentIdentifier)] {
        var counts: [PersistentIdentifier: (group: CategoryGroup, count: Int)] = [:]
        for raw in selectedUnmappedCategories {
            let group = bulkCategoryAssignments[raw] ?? bulkCategoryGroup ?? getOrCreateDefaultExpensesGroup()
            let id = group.persistentModelID
            if var entry = counts[id] {
                entry.count += 1
                counts[id] = entry
            } else {
                counts[id] = (group, 1)
            }
        }
        return counts.values
            .map { ($0.group, $0.count, $0.group.persistentModelID) }
            .sorted { $0.0.order < $1.0.order }
    }

    private func applyBulkGroupingMode() {
        switch bulkGroupingMode {
        case .single:
            if let group = bulkCategoryGroup {
                assignAllSelected(to: group)
            }
        case .smart:
            bulkCategoryAssignments = smartAssignments(for: selectedUnmappedCategories)
        case .custom:
            if bulkCategoryAssignments.isEmpty {
                bulkCategoryAssignments = smartAssignments(for: selectedUnmappedCategories)
            }
        }
    }

    private func assignAllSelected(to group: CategoryGroup) {
        for raw in selectedUnmappedCategories {
            bulkCategoryAssignments[raw] = group
        }
    }

    private func createBulkGroupAndAssignIfNeeded() {
        let trimmed = bulkNewGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = getOrCreateGroup(named: trimmed, type: bulkNewGroupType)
        bulkCreatedGroups.append(group)
        if bulkAssignNewGroupToSelection {
            assignAllSelected(to: group)
        }
        bulkNewGroupName = ""
        bulkNewGroupType = .expense
    }

    private func smartAssignments(for rawCategories: Set<String>) -> [String: CategoryGroup] {
        var assignments: [String: CategoryGroup] = [:]
        for raw in rawCategories {
            assignments[raw] = smartGroup(for: raw)
        }
        return assignments
    }

    private func smartGroup(for raw: String) -> CategoryGroup {
        let normalized = raw.lowercased()
        let tokens = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        let incomeKeywords: Set<String> = [
            "income", "salary", "payroll", "paycheck", "bonus", "interest", "dividend", "refund"
        ]
        if !tokens.isEmpty, !incomeKeywords.intersection(tokens).isEmpty {
            return getOrCreateIncomeGroup()
        }

        let expenseMap: [(keywords: [String], groupName: String)] = [
            (["rent", "mortgage", "housing", "lease"], "Housing"),
            (["grocery", "groceries", "supermarket", "market"], "Groceries"),
            (["restaurant", "dining", "cafe", "coffee", "takeout"], "Dining"),
            (["utility", "utilities", "electric", "water", "gas", "internet", "wifi"], "Utilities"),
            (["transport", "transit", "uber", "lyft", "fuel", "gasoline", "parking"], "Transportation"),
            (["insurance", "premium"], "Insurance"),
            (["health", "medical", "pharmacy", "doctor", "dental"], "Healthcare"),
            (["entertainment", "movie", "music", "stream", "netflix", "spotify"], "Entertainment"),
            (["travel", "hotel", "airline", "flight"], "Travel"),
            (["education", "tuition", "school", "books"], "Education"),
            (["child", "kids", "childcare", "daycare"], "Kids"),
            (["phone", "cell", "mobile"], "Phone"),
            (["home", "maintenance", "repair"], "Home"),
            (["subscription", "membership"], "Subscriptions")
        ]

        for entry in expenseMap {
            if entry.keywords.contains(where: { tokens.contains($0) || normalized.contains($0) }) {
                return getOrCreateGroup(named: entry.groupName, type: .expense)
            }
        }

        return getOrCreateDefaultExpensesGroup()
    }

    private func getOrCreateIncomeGroup() -> CategoryGroup {
        if let existing = allGroups.first(where: { $0.type == .income }) {
            return existing
        }
        let maxOrder = allGroups.map(\.order).max() ?? -1
        let newGroup = CategoryGroup(name: "Income", order: maxOrder + 1, type: .income)
        modelContext.insert(newGroup)
        allGroups.append(newGroup)
        _ = modelContext.safeSave(context: "ImportDataView.getOrCreateIncomeGroup", showErrorToUser: false)
        return newGroup
    }

    private func getOrCreateGroup(named name: String, type: CategoryGroupType) -> CategoryGroup {
        if let existing = allGroups.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame && $0.type == type }) {
            return existing
        }
        let maxOrder = allGroups.map(\.order).max() ?? -1
        let newGroup = CategoryGroup(name: name, order: maxOrder + 1, type: type)
        modelContext.insert(newGroup)
        allGroups.append(newGroup)
        _ = modelContext.safeSave(context: "ImportDataView.getOrCreateGroup", showErrorToUser: false)
        return newGroup
    }

	    func startCreatingCategory(for raw: String, prefill: Bool) {
        newCategoryName = prefill ? raw : ""
        newCategoryGroup = getOrCreateDefaultExpensesGroup()
        
        // Reset/Default group creation state
        isCreatingNewGroup = false
        newGroupNameRaw = ""
        newGroupType = .expense
        
        categoryCreationTarget = CategoryCreationTarget(rawCategory: raw)
    }
    
	    func createCategory(for raw: String) {
        var targetGroup: CategoryGroup?
        var createdGroup: CategoryGroup? = nil

        if isCreatingNewGroup {
            let newGroup = CategoryGroup(name: newGroupNameRaw, type: newGroupType)
            modelContext.insert(newGroup)
            // Add to local list to keep UI in sync
            allGroups.append(newGroup)
            // Re-sort roughly? Or just append.
            targetGroup = newGroup
            createdGroup = newGroup
        } else {
            targetGroup = newCategoryGroup
        }

        guard let group = targetGroup else { return }
        
        // Create new category
        let newCat = Category(name: newCategoryName)
        newCat.group = group
        modelContext.insert(newCat)
        
        allCategories.append(newCat)
        categoryMapping[raw] = newCat

        // Save context
        guard modelContext.safeSave(context: "ImportDataView.createCategory", showErrorToUser: false) else {
            // Rollback on failure
            if let createdGroup {
                allGroups.removeAll { $0.persistentModelID == createdGroup.persistentModelID }
                modelContext.delete(createdGroup)
            }
            allCategories.removeAll { $0.persistentModelID == newCat.persistentModelID }
            categoryMapping[raw] = nil
            modelContext.delete(newCat)
            errorMessage = "Couldn't create category. Please try again."
            return
        }

        categoryCreationTarget = nil
	    }

		    // MARK: - Account Mapping Helpers

            func suggestedAccountType(for rawAccountName: String) -> AccountType {
                let lower = rawAccountName.lowercased()
                let tokens = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                let collapsed = lower
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")

                if tokens.contains("mortgage") { return .mortgage }
                if tokens.contains("loan") || tokens.contains("loans") { return .loans }

                if collapsed.contains("lineofcredit") || tokens.contains("loc") {
                    return .lineOfCredit
                }

	                if tokens.contains("credit") ||
	                    collapsed.contains("creditcard") ||
	                    tokens.contains("visa") ||
	                    collapsed.contains("mastercard") ||
	                    tokens.contains("amex") ||
	                    collapsed.contains("americanexpress") ||
	                    tokens.contains("discover") {
	                    return .creditCard
	                }

                if tokens.contains("savings") || tokens.contains("saving") { return .savings }
                if tokens.contains("chequing") || tokens.contains("checking") { return .chequing }

                if tokens.contains("investment") ||
                    tokens.contains("invest") ||
                    tokens.contains("brokerage") ||
                    tokens.contains("rrsp") ||
                    tokens.contains("tfsa") ||
                    tokens.contains("ira") ||
                    tokens.contains("401k") {
                    return .investment
                }

                return .chequing
            }

		    func startCreatingAccount(for raw: String, prefill: Bool) {
		        newAccountName = prefill ? raw : ""
		        newAccountType = suggestedAccountType(for: raw)
		        newAccountBalanceInput = ""
		        accountCreationTarget = AccountCreationTarget(rawAccount: raw)
		    }

	    func createAccountFromImportMapping(rawAccount: String) {
	        let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }

	        if let existing = accounts.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	            accountMapping[rawAccount] = existing
	            accountCreationTarget = nil
	            return
	        }

	        let balance = ImportParser.parseAmount(newAccountBalanceInput) ?? 0
	        let account = Account(name: trimmed, type: newAccountType, balance: balance)
	        modelContext.insert(account)
	        accountMapping[rawAccount] = account
	        guard modelContext.safeSave(context: "ImportDataView.createAccountFromImportMapping", showErrorToUser: false) else {
                modelContext.delete(account)
                accountMapping[rawAccount] = nil
                errorMessage = "Couldn’t create the account. Please try again."
                return
            }
	        accountCreationTarget = nil
	    }

	    func currencySymbol(for code: String) -> String {
	        let formatter = NumberFormatter()
	        formatter.numberStyle = .currency
	        formatter.currencyCode = code
	        formatter.maximumFractionDigits = 0
	        return formatter.currencySymbol ?? code
	    }
}
