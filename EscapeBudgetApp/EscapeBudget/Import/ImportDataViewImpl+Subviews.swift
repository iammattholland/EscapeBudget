import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

    // MARK: - Subviews

// Helper for sheet
struct CategoryCreationTarget: Identifiable {
    let id = UUID()
    let rawCategory: String
}

struct TagCreationTarget: Identifiable {
    let id = UUID()
    let rawTag: String
}

struct AccountCreationTarget: Identifiable {
    let id = UUID()
    let rawAccount: String
}

struct ImportProcessingOptionsSheet: View {
    @Binding var options: ImportProcessingOptions
    let onUseOnce: () -> Void
    let onMakeDefault: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
	            Section {
	                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
	                    Text("Import Processing")
	                        .appSectionTitleText()
	                    Text("Choose what Escape Budget should do during this import. You can use these options once, or set them as your default for future imports.")
	                        .appSecondaryBodyText()
	                        .foregroundStyle(.secondary)
	                }
	                .padding(.vertical, AppDesign.Theme.Spacing.micro)
	            }

	            Section {
	                Toggle("Clean up payee names", isOn: $options.normalizePayee)
	                Toggle("Apply auto rules", isOn: $options.applyAutoRules)
	                Toggle("Detect duplicates", isOn: $options.detectDuplicates)
	                Toggle("Suggest transfers for review", isOn: $options.suggestTransfers)
	                Toggle("Save processing history", isOn: $options.saveProcessingHistory)
	            } header: {
	                Text("Options")
	            } footer: {
	                Text("Transfers are never auto-linked without your confirmation.")
	            }

	            Section("Summary") {
	                Text(options.summary)
	                    .appSecondaryBodyText()
	                    .foregroundStyle(.secondary)
	            }
        }
        .navigationTitle("Before You Import")
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button("Use Once") { onUseOnce() }
                    Button("Make Default") { onMakeDefault() }
                } label: {
                    Text("Continue")
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ColumnMappingRowView: View {
    let header: String
    let colIndex: Int
    @Binding var columnMapping: [Int: String]
    let previewValue: String?
    @Environment(\.appColorMode) var appColorMode
    
    var body: some View {
	        HStack {
	            VStack(alignment: .leading) {
	                Text(header)
	                    .appSectionTitleText()
	                    .lineLimit(1)
                
                if let val = previewValue {
                    Text("Ex: \(val)")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                Button("Skip") { setMapping("skip") }
                Divider()
                Button("Date") { setMapping("Date") }
                Button("Payee") { setMapping("Payee") }
                Button("Amount") { setMapping("Amount") }
                Button("Memo") { setMapping("Memo") }
                Button("Category") { setMapping("Category") }
                Button("Account") { setMapping("Account") }
                Button("Tags") { setMapping("Tags") }
                Button("Kind") { setMapping(ColumnType.kind.rawValue) }
                Button("Transfer ID") { setMapping(ColumnType.transferID.rawValue) }
                Button("External Transfer Label") { setMapping(ColumnType.externalTransferLabel.rawValue) }
                Button("Transfer Inbox Dismissed") { setMapping(ColumnType.transferInboxDismissed.rawValue) }
                Button("Purchase Items") { setMapping(ColumnType.purchaseItems.rawValue) }
                // Inflow/Outflow/Status hidden from manual mapper as per user request
                // They are handled via Templates (e.g. YNAB)
            } label: {
                HStack {
                    Text(currentLabel)
                        .foregroundStyle(isMapped ? .white : .primary)
                    Image(systemName: "chevron.down")
                        .appCaptionText()
                        .foregroundStyle(isMapped ? .white : .secondary)
                }
	                .padding(.vertical, AppDesign.Theme.Spacing.xSmall)
	                .padding(.horizontal, AppDesign.Theme.Spacing.small)
	                .background(isMapped ? AppDesign.Colors.tint(for: appColorMode) : Color(.systemGray5))
	                .cornerRadius(AppDesign.Theme.Radius.xSmall)
	            }
	        }
	        .padding(.vertical, AppDesign.Theme.Spacing.micro)
	    }
    
    func setMapping(_ val: String) {
        columnMapping[colIndex] = val
    }
    
    var isMapped: Bool {
        let val = columnMapping[colIndex]
        return val != nil && val != "skip"
    }
    
    var currentLabel: String {
        columnMapping[colIndex] ?? "Skip"
    }
}

struct PreviewTransactionRow: View {
    let transaction: Transaction
    let currencyCode: String
    @Environment(\.appColorMode) var appColorMode
    
    var body: some View {
	        HStack {
	            VStack(alignment: .leading) {
	                Text(transaction.payee)
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
	                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
	                    .appCaptionText()
	                    .foregroundStyle(.secondary)
	            }
            Spacer()
            Text(transaction.amount, format: .currency(code: currencyCode))
                .foregroundStyle(transaction.amount >= 0 ? AppDesign.Colors.success(for: appColorMode) : .primary)
        }
    }
}

// MARK: - Legacy / Utils
// Note: TransactionParser is no longer used.

struct CSVDocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.escapeBudgetEncryptedExport, .commaSeparatedText, .plainText],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: CSVDocumentPicker
        
        init(parent: CSVDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
