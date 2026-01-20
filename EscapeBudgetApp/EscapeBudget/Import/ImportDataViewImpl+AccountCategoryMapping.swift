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
	                            .foregroundStyle(AppColors.success(for: appColorMode))
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
	                                .font(AppTheme.Typography.body)
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
	                                            .foregroundStyle(AppColors.success(for: appColorMode))
	                                    } else {
	                                        Text("Use Default")
	                                            .foregroundStyle(.secondary)
	                                        Image(systemName: "chevron.up.chevron.down")
	                                            .appCaptionText()
	                                    }
	                                }
		                                .padding(.horizontal, AppTheme.Spacing.compact)
		                                .padding(.vertical, AppTheme.Spacing.micro)
		                                .background(Color(.secondarySystemBackground))
		                                .cornerRadius(AppTheme.Radius.xSmall)
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
	            .buttonStyle(.borderedProminent)
	            .controlSize(.large)
	            .padding()
	        }
	        .sheet(item: $accountCreationTarget) { target in
	            NavigationStack {
	                Form {
	                    Section {
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
	                            Text("Imported Value")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
		                            Text(target.rawAccount)
		                                .appSectionTitleText()
		                        }
		                    }

	                    Section("Details") {
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
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

	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
	                            Text("Starting Balance")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
	                            HStack(spacing: AppTheme.Spacing.compact) {
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
	            .presentationDetents([.medium])
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
                                    .foregroundStyle(AppColors.tint(for: appColorMode))
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                                    Text("Create All Unmapped Categories")
                                        .font(AppTheme.Typography.body)
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
                            .foregroundStyle(AppColors.success(for: appColorMode))
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
                                .font(AppTheme.Typography.body)
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
                                            .foregroundStyle(AppColors.success(for: appColorMode))
                                    } else {
                                        Text("Select Category")
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .appCaptionText()
                                    }
                                }
		                                .padding(.horizontal, AppTheme.Spacing.compact)
		                                .padding(.vertical, AppTheme.Spacing.micro)
		                                .background(Color(.secondarySystemBackground))
		                                .cornerRadius(AppTheme.Radius.xSmall)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .sheet(item: $categoryCreationTarget) { target in
            NavigationStack {
                Form {
	                    Section {
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
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
                                .foregroundStyle(AppColors.tint(for: appColorMode))
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
                                    .foregroundStyle(AppColors.tint(for: appColorMode))
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
	                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
	                            Text("Create \(selectedUnmappedCategories.count) Categories")
	                                .appSectionTitleText()
	                            Text("These categories will be created and automatically mapped to your import data.")
	                                .appCaptionText()
	                                .foregroundStyle(.secondary)
	                        }
	                    }

                    Section {
                        ForEach(unmappedCategories, id: \.self) { raw in
                            HStack {
                                Image(systemName: selectedUnmappedCategories.contains(raw) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedUnmappedCategories.contains(raw) ? AppColors.tint(for: appColorMode) : .gray)
                                Text(raw)
                                    .font(AppTheme.Typography.body)
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
	                                        .foregroundStyle(AppColors.tint(for: appColorMode))
	                                }
                            }
                        }
                        .textCase(nil)
                    }

                    Section("Destination Group") {
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
                    }
                }
                .navigationTitle("Bulk Create")
                .navigationBarTitleDisplayMode(.inline)
                .globalKeyboardDoneToolbar()
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
                        .disabled(selectedUnmappedCategories.isEmpty || (bulkCreateNewGroup ? bulkNewGroupName.isEmpty : bulkCategoryGroup == nil))
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
        // Reset group selection - exclude transfer groups
        bulkCategoryGroup = allGroups.filter { $0.type != .transfer }.first
        bulkCreateNewGroup = false
        bulkNewGroupName = ""
        bulkNewGroupType = .expense
        showingBulkCategoryCreation = true
    }

	    func performBulkCategoryCreation() {
        var targetGroup: CategoryGroup

        var createdGroup: CategoryGroup? = nil
        var createdCategories: [Category] = []

        if bulkCreateNewGroup {
            let newGroup = CategoryGroup(name: bulkNewGroupName, type: bulkNewGroupType)
            modelContext.insert(newGroup)
            allGroups.append(newGroup)
            targetGroup = newGroup
            createdGroup = newGroup
        } else {
            guard let group = bulkCategoryGroup else { return }
            targetGroup = group
        }

        // Create all selected categories
        for rawCategory in selectedUnmappedCategories {
            let newCat = Category(name: rawCategory)
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

	    func startCreatingCategory(for raw: String, prefill: Bool) {
        newCategoryName = prefill ? raw : ""
        newCategoryGroup = allGroups.first
        
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
