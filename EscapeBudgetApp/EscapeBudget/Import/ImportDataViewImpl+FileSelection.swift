import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    // MARK: - File Selection View
	    var fileSelectionView: some View {
        VStack(spacing: AppDesign.Theme.Spacing.xLarge) {
            Image(systemName: "doc.text")
                .appIconHero()
                .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))

            VStack(spacing: AppDesign.Theme.Spacing.tight) {
                Text("Import Data from CSV")
                    .appTitleText()
                    .fontWeight(.semibold)

                Text("Select a CSV file to import transaction data. Supports large files and various bank formats.")
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
            }
            
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                Text("Import Template")
                    .appSectionTitleText()

                Menu {
                    ForEach(sortedImportSources) { source in
                        Button {
                            selectedImportSource = source
                            lastUsedSourceRaw = source.rawValue
                            autoMapColumns()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(source.rawValue)
                                Text(source.description)
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                            Text(selectedImportSource.rawValue)
                                .foregroundStyle(.primary)
                            Text(selectedImportSource.description)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(AppDesign.Theme.Radius.xSmall)
                }
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                Text(initialAccount == nil ? "Default Account" : "Destination Account")
                    .appSectionTitleText()
                if accounts.isEmpty {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.small) {
                        Text("Create an account to import transactions into.")
                            .appSecondaryBodyText()
                            .foregroundStyle(.secondary)

		                        Button {
		                            beginCreateAccountFromFileSelection()
		                        } label: {
		                            Label("Create Account", systemImage: "plus.circle")
		                                .frame(maxWidth: .infinity)
		                        }
		                        .appPrimaryCTA()
		                    }
		                    .padding(AppDesign.Theme.Spacing.tight)
		                    .background(Color(.secondarySystemGroupedBackground))
		                    .cornerRadius(AppDesign.Theme.Radius.compact)
		                } else {
	                    if let initialAccount {
                        let destination = defaultAccount ?? initialAccount
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.xSmall) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                    Text(destination.name)
                                        .appBodyStrongText()
                                    Text(destination.type.rawValue)
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(accounts) { account in
                                        Button {
                                            defaultAccount = account
                                        } label: {
                                            HStack {
                                                Text(account.name)
                                                if account.persistentModelID == destination.persistentModelID {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Change")
                                }
                            }

                            Text("If your CSV includes an Account column and you map it, Escape Budget will import per-row accounts; otherwise it will use this destination account.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
	                        }
	                        .padding(AppDesign.Theme.Spacing.tight)
	                        .background(Color(.secondarySystemGroupedBackground))
	                        .cornerRadius(AppDesign.Theme.Radius.compact)
	                    } else {
	                        Picker("Default Account", selection: $defaultAccount) {
	                            Text("Select").tag(Optional<Account>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

            Button(action: { showFileImporter = true }) {
                Label("Select CSV File", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
            .controlSize(.large)
            .disabled(accounts.isEmpty)
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
	        .onAppear {
	            if defaultAccount == nil {
	                defaultAccount = initialAccount ?? accounts.first
	            }
	        }
	    }

	    func beginCreateAccountFromFileSelection() {
	        newAccountName = ""
	        newAccountType = .chequing
	        newAccountBalanceInput = ""
	        showingCreateAccountSheet = true
	    }

	    @MainActor
	    func createAccountAndReturnToImport() {
	        let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard !trimmed.isEmpty else { return }

	        if let existing = accounts.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	            defaultAccount = existing
	            showingCreateAccountSheet = false
	            return
	        }

	        let balance = ImportParser.parseAmount(newAccountBalanceInput) ?? 0
	        let account = Account(name: trimmed, type: newAccountType, balance: balance)
	        modelContext.insert(account)
	        guard modelContext.safeSave(context: "ImportDataView.createAccountAndReturnToImport", showErrorToUser: false) else {
                modelContext.delete(account)
                errorMessage = "Couldn’t create the account. Please try again."
                return
            }
	        defaultAccount = account
	        showingCreateAccountSheet = false
	    }
}
