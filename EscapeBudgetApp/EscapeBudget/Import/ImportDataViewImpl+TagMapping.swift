import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
	    // MARK: - Tag Mapping View
		    var tagMappingView: some View {
	        VStack {
	            Text("Map Tags")
	                .appSectionTitleText()
	                .padding()

            Text("Match tags from your file to your Escape Budget tags.")
                .appCaptionText()
                .foregroundStyle(.secondary)

            List {
                ForEach(importedTags, id: \.self) { raw in
                    HStack {
                        Text(raw)
                            .font(AppDesign.Theme.Typography.body)
                        Spacer()

                        Menu {
                            Button("Create '\(raw)'...") {
                                startCreatingTag(for: raw, prefill: true)
                            }

                            Button("Create New...") {
                                startCreatingTag(for: raw, prefill: false)
                            }

                            Divider()

                            ForEach(allTransactionTags) { tag in
                                Button(tag.name) {
                                    ignoredImportedTags.remove(raw)
                                    tagMapping[raw] = tag
                                }
                            }

                            Divider()

                            Button("Ignore", role: .destructive) {
                                ignoredImportedTags.insert(raw)
                                tagMapping.removeValue(forKey: raw)
                            }
                        } label: {
                            HStack(spacing: AppDesign.Theme.Spacing.compact) {
                                if ignoredImportedTags.contains(raw) {
                                    Text("Ignored")
                                        .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                } else if let mapped = tagMapping[raw] {
                                    TransactionTagChip(tag: mapped)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                                } else {
                                    Text("Will Create")
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
		            }

            Button("Next") {
                checkForDuplicates()
                currentStep = .review
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding()
        }
        .sheet(item: $tagCreationTarget) { target in
            NavigationStack {
                Form {
                    Section("Imported Value") {
                        Text(target.rawTag)
                            .foregroundStyle(.secondary)
                    }

                    Section("Tag Details") {
                        VStack(alignment: .leading) {
                            TextField("Tag Name", text: $newTagName)
                            if newTagName != target.rawTag {
                                Button("Use Imported Name") {
                                    newTagName = target.rawTag
                                }
                                .appCaptionText()
                                .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppDesign.Theme.Spacing.tight), count: 5), spacing: AppDesign.Theme.Spacing.tight) {
                            ForEach(TagColorPalette.options(for: appColorMode), id: \.hex) { option in
                                Circle()
                                    .fill(Color(hex: option.hex) ?? AppDesign.Colors.tint(for: appColorMode))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(newTagColorHex == option.hex ? Color.primary : Color.clear, lineWidth: 3)
                                    )
                                    .onTapGesture { newTagColorHex = option.hex }
                            }
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.micro)
                    }
                }
                .navigationTitle("Create Tag")
                .navigationBarTitleDisplayMode(.inline)
                .globalKeyboardDoneToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { tagCreationTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createTag(for: target.rawTag)
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .solidPresentationBackground()
        }
    }

    func startCreatingTag(for raw: String, prefill: Bool) {
        newTagName = prefill ? raw : ""
        newTagColorHex = TagColorPalette.defaultHex(for: appColorMode)
        tagCreationTarget = TagCreationTarget(rawTag: raw)
    }

	    func createTag(for raw: String) {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = allTransactionTags.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            ignoredImportedTags.remove(raw)
            tagMapping[raw] = existing
            tagCreationTarget = nil
            return
        }

        let nextOrder = (allTransactionTags.map(\.order).max() ?? -1) + 1
        let tag = TransactionTag(name: trimmed, colorHex: newTagColorHex, order: nextOrder)
        modelContext.insert(tag)
        allTransactionTags.append(tag)
        ignoredImportedTags.remove(raw)
        tagMapping[raw] = tag
        tagCreationTarget = nil
    }
    
	    func toggleSelectAll() {
        let allSelected = stagedTransactions.allSatisfy { $0.isSelected }
        for index in stagedTransactions.indices {
            stagedTransactions[index].isSelected = !allSelected
        }
    }
}
