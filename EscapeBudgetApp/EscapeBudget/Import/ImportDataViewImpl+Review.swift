import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    // MARK: - Review Import View
    var reviewImportView: some View {
        VStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Found")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("\(stagedTransactions.count)")
                                .appSectionTitleText()
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Duplicates")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("\(stagedTransactions.filter { $0.isDuplicate }.count)")
                                .appSectionTitleText()
                                .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("To Import")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("\(stagedTransactions.filter { $0.isSelected }.count)")
                                .appSectionTitleText()
                                .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                        }
                    }
                    .padding(.vertical, AppDesign.Theme.Spacing.micro)
                } header: {
                    Text("Summary")
                }
                
                Section {
                    Button(action: toggleExcludeDuplicates) {
                        Label("Exclude All Duplicates", systemImage: "rectangle.badge.xmark")
                    }
                    Button(action: selectAllNonDuplicates) {
                        Label("Select All (Non-Duplicates)", systemImage: "checkmark.circle")
                    }
                    Button(action: toggleSelectAll) {
                        Label("Toggle Select All", systemImage: "circle.dashed")
                    }
                }

                if importOptions.suggestTransfers {
                    Section {
                        Button {
                            showingTransferSuggestionSheet = true
                        } label: {
                            Label("Review Transfer Suggestions", systemImage: "sparkles")
                        }

                        Button {
                            refreshTransferSuggestions()
                        } label: {
                            Label("Refresh Suggestions", systemImage: "arrow.clockwise")
                        }

                        if transferSuggestionCount > 0 {
                            Text("\(transferSuggestionCount) transfer pair\(transferSuggestionCount == 1 ? "" : "s") linked.")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Transfer Suggestions")
                    } footer: {
                        Text("Review suggested pairs before linking. Linking clears categories and excludes them from income/expense stats.")
                    }
                }
                
                Section("Transactions") {
                    ForEach($stagedTransactions) { $tx in
                        HStack {
                            Image(systemName: tx.isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(tx.isSelected ? AppDesign.Colors.tint(for: appColorMode) : .gray)
                                .onTapGesture {
                                    tx.isSelected.toggle()
                                }
                            
                            VStack(alignment: .leading) {
                                Text(tx.payee)
                                    .font(AppDesign.Theme.Typography.body)
                                    .fontWeight(.medium)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)

	                                if tx.kind == .transfer, tx.transferID != nil {
	                                    Text("Transfer (linked)")
	                                        .appCaption2Text()
	                                        .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
	                                        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
	                                        .background(AppDesign.Colors.tint(for: appColorMode).opacity(0.12))
	                                        .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
	                                        .cornerRadius(AppDesign.Theme.Radius.mini)
	                                }
                                
                                if let raw = tx.rawCategory {
                                    if let mapped = categoryMapping[raw] {
                                        HStack(spacing: AppDesign.Theme.Spacing.micro) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .appCaption2Text()
                                            Text(mapped.name)
                                                .appCaptionText()
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
		                                        .padding(.vertical, AppDesign.Theme.Spacing.nano)
		                                        .background(AppDesign.Colors.success(for: appColorMode).opacity(0.15))
		                                        .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
		                                        .cornerRadius(AppDesign.Theme.Radius.mini)
		                                    } else {
                                        HStack(spacing: AppDesign.Theme.Spacing.micro) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .appCaption2Text()
                                            Text("Unmapped: \(raw)")
                                                .appCaptionText()
                                        }
                                        .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
		                                        .padding(.vertical, AppDesign.Theme.Spacing.nano)
		                                        .background(AppDesign.Colors.warning(for: appColorMode).opacity(0.15))
		                                        .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
		                                        .cornerRadius(AppDesign.Theme.Radius.mini)
		                                    }
	                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: AppDesign.Theme.Spacing.xSmall) {
                                Text(tx.amount.formatted(.currency(code: currencyCode)))
                                    .font(AppDesign.Theme.Typography.body)
                                    .foregroundStyle(tx.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary)

                                if tx.kind == .transfer, let id = tx.transferID {
                                    Button {
                                        editingTransferLink = TransferLinkEditorDestination(id: id)
                                    } label: {
                                        Label("Linked", systemImage: "link")
                                            .appCaption2Text()
                                            .labelStyle(.iconOnly)
                                            .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Edit linked transfer")
                                }
                                
	                                if tx.isDuplicate {
	                                    Text("Duplicate")
	                                        .appCaption2Text()
	                                        .padding(.horizontal, AppDesign.Theme.Spacing.xSmall)
	                                        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
	                                        .background(AppDesign.Colors.warning(for: appColorMode).opacity(0.2))
	                                        .foregroundStyle(AppDesign.Colors.warning(for: appColorMode))
	                                        .cornerRadius(AppDesign.Theme.Radius.mini)

	                                    if let reason = tx.duplicateReason, !reason.isEmpty {
	                                        Text(reason)
	                                            .appCaption2Text()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tx.isSelected.toggle()
                        }
                    }
                }
            }
            
            Button(action: { performFinalImport() }) {
                Text("Finish Import (\(stagedTransactions.filter { $0.isSelected }.count))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding()
            .disabled(stagedTransactions.filter { $0.isSelected }.isEmpty)
        }
        .sheet(isPresented: $showingTransferSuggestionSheet) {
            NavigationStack {
                ImportTransferSuggestionsView(
                    currencyCode: currencyCode,
                    suggestions: transferSuggestions,
                    selectedIDs: $selectedTransferSuggestionIDs,
                    transactionLookup: { id in stagedTransactions.first(where: { $0.id == id }) },
                    accountNameFor: accountNameForImported(_:),
                    onRefresh: { refreshTransferSuggestions() },
                    onLinkSelected: { linkSelectedTransferSuggestions() }
                )
            }
        }
        .sheet(item: $editingTransferLink) { destination in
            NavigationStack {
                ImportTransferLinkEditor(
                    transferID: destination.id,
                    currencyCode: currencyCode,
                    onUnlink: { unlinkTransfer(id: destination.id) },
                    legsLookup: { id in stagedTransactions.filter { $0.transferID == id } },
                    accountNameFor: accountNameForImported(_:)
                )
            }
        }
    }
    
    func toggleExcludeDuplicates() {
        for index in stagedTransactions.indices {
            if stagedTransactions[index].isDuplicate {
                stagedTransactions[index].isSelected = false
            }
        }
    }

    func selectAllNonDuplicates() {
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !stagedTransactions[index].isDuplicate
        }
    }
}
