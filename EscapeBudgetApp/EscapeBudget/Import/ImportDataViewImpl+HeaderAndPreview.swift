import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    // MARK: - Header Selection View
    var headerSelectionView: some View {
        VStack(spacing: AppDesign.Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                Text("Select Header Row")
                    .appSectionTitleText()
                Text("Tap the row that contains column names (Date, Amount, etc.)")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

            headerPreviewTable
            
            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                Text("Date Format (Optional)")
                    .appSecondaryBodyText()
                    .fontWeight(.semibold)
                
                HStack {
                    Picker("Date Format", selection: $selectedDateFormat) {
                        Text("Auto Detect").tag(nil as DateFormatOption?)
                        ForEach(DateFormatOption.allCases) { format in
                            Text(format.rawValue).tag(Optional(format))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Spacer()
                }

                Text("If dates aren't parsing correctly, specify the format used in your file.")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(AppDesign.Theme.Radius.button)
            .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
    
    var headerPreviewTable: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<previewRows.count, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        // Row Number
                        Text("\(rowIndex + 1)")
                            .appCaption2Text()
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .center)
                            .padding(.vertical, AppDesign.Theme.Spacing.compact)
                            .background(Color(.systemGray6))
                        
                        // Columns
                        ForEach(Array(previewRows[rowIndex].enumerated()), id: \.offset) { column in
                            Text(column.element.isEmpty ? " " : column.element)
                                .appCaptionText()
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                                .padding(.vertical, AppDesign.Theme.Spacing.compact)
                                .padding(.horizontal, AppDesign.Theme.Spacing.compact)
                                .background(rowBackground(for: rowIndex))
                                .contentShape(Rectangle())
                        }
                    }
                    .background(rowBackground(for: rowIndex))
                    .border(rowIndex == headerRowIndex ? AppDesign.Colors.tint(for: appColorMode) : Color.clear, width: 2)
                    .onTapGesture {
                        headerRowIndex = rowIndex
                    }
                }
            }
	        }
	        .frame(maxHeight: 300)
	        .background(Color(.systemBackground))
	        .cornerRadius(AppDesign.Theme.Radius.xSmall)
	        .overlay(
	            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.xSmall)
	                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
	        )
	        .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
	    }
    
    func rowBackground(for index: Int) -> Color {
        if index == headerRowIndex {
            return AppDesign.Colors.tint(for: appColorMode).opacity(0.1)
        }
        return index % 2 == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5)
    }

    // MARK: - Column Mapping View
    var columnMappingView: some View {
        VStack(spacing: 0) {
            if previewRows.indices.contains(headerRowIndex) {
                 List {
                     Section {
                         ForEach(0..<previewRows[headerRowIndex].count, id: \.self) { colIndex in
                             let header = previewRows[headerRowIndex][colIndex]
                             if !header.isEmpty {
                                 ColumnMappingRowView(
                                     header: header,
                                     colIndex: colIndex,
                                     columnMapping: $columnMapping,
                                     previewValue: getPreviewValue(col: colIndex)
                                 )
                             }
                         }
                     } header: {
                         Text("Map Columns")
                     } footer: {
                         let valid = canAdvanceToPreview
                         if !valid {
                             Text("Please map at least Date and Amount columns.")
                                 .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                         }
                     }
                 }
            } else {
                Text("Invalid header row selected")
            }
        }
    }
    
    func getPreviewValue(col: Int) -> String? {
        // Show value from first data row (header + 1)
        let dataRowIdx = headerRowIndex + 1
        if previewRows.indices.contains(dataRowIdx), previewRows[dataRowIdx].indices.contains(col) {
            return previewRows[dataRowIdx][col]
        }
        return nil
    }

    // MARK: - Preview View
    var previewView: some View {
        List {
            Section("Summary") {
                LabeledContent("File", value: selectedFileURL?.lastPathComponent ?? "Unknown")
                LabeledContent("Header Row", value: "\(headerRowIndex + 1)")
                LabeledContent("Mapped Columns", value: "\(columnMapping.values.filter { $0 != "skip" }.count)")
            }

            Section("Import Settings") {
                if accounts.isEmpty {
                    Text("Create an account first, then import transactions.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default Account", selection: $defaultAccount) {
                        Text("Select").tag(Optional<Account>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                }

                let hasAccountColumn = columnMapping.values.contains("Account")
                if hasAccountColumn {
                    Text("Account column is mapped; Escape Budget will try to match accounts by name per row and fall back to the default account when missing.")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    Text("Amount Signs")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                    Picker("Amount Signs", selection: $signConvention) {
                        Text("Select").tag(Optional<AmountSignConvention>.none)
                        ForEach(AmountSignConvention.allCases) { convention in
                            Text(convention.rawValue).tag(Optional(convention))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    if let convention = signConvention {
                        Text(convention.detail)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Required before import.")
                            .appCaptionText()
                            .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                    }
                }
            }

	            Section {
	                LabeledContent("This import", value: importOptions.summary)

	                Button {
	                    hasConfiguredImportOptionsThisRun = true
	                    showingImportOptionsSheet = true
	                } label: {
	                    Label("Review processing options", systemImage: "slider.horizontal.3")
	                }
	            } header: {
	                Text("Processing")
	            } footer: {
	                Text("These options control payee cleanup, auto rules, duplicate detection, and transfer suggestions for this import.")
	            }
            
            Section("Data Preview (First 5 Items)") {
                let dataRows = Array(previewRows.dropFirst(headerRowIndex + 1).prefix(5))
                ForEach(0..<dataRows.count, id: \.self) { i in
                    let row = dataRows[i]
                    if let tx = createTransaction(
                        from: row,
                        headers: previewRows[headerRowIndex],
                        columnMapping: columnMapping,
                        dateFormatOption: selectedDateFormat,
                        signConvention: signConvention ?? .positiveIsIncome
                    ) {
                        PreviewTransactionRow(transaction: tx, currencyCode: currencyCode)
                    } else {
                        Text("Row \(i + headerRowIndex + 2): Invalid / Skipped")
                            .appCaptionText()
                            .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                    }
                }
            }
            
            Section {
                 Text("This will verify your mapping on a few rows. If everything looks good, tap Import.")
                     .appCaptionText()
                     .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if !hasConfiguredImportOptionsThisRun {
                importOptions = ImportProcessingOptions(
                    normalizePayee: normalizePayeeOnImport,
                    applyAutoRules: applyAutoRulesOnImport,
                    detectDuplicates: detectDuplicatesOnImport,
                    suggestTransfers: suggestTransfersOnImport,
                    saveProcessingHistory: saveProcessingHistory
                )
            }
        }
    }

    // MARK: - Importing View
}
