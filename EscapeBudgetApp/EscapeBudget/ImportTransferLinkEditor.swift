import SwiftUI

struct ImportTransferLinkEditor: View {
    @Environment(\.dismiss) private var dismiss

    let transferID: UUID
    let currencyCode: String
    let onUnlink: () -> Void

    let legsLookup: (UUID) -> [ImportedTransaction]
    let accountNameFor: (ImportedTransaction) -> String

    var body: some View {
        List {
            let legs = legsLookup(transferID)

            if legs.count >= 2 {
                Section("Linked Transfer") {
                    ForEach(legs) { tx in
	                        HStack(spacing: AppDesign.Theme.Spacing.tight) {
	                            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.nano) {
	                                Text(accountNameFor(tx))
	                                    .appSecondaryBodyText()
	                                    .fontWeight(.semibold)
                                    Text(tx.date, format: .dateTime.month(.abbreviated).day().year())
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                Text(tx.payee)
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(tx.amount, format: .currency(code: currencyCode))
                                .appSecondaryBodyText()
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.hairline)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onUnlink()
                        dismiss()
                    } label: {
                        Label("Unlink Transfer", systemImage: "link.badge.minus")
                    }
                } footer: {
                    Text("Unlinking makes both transactions standard again so they can be categorized normally.")
                }
            } else {
                ContentUnavailableView(
                    "Transfer",
                    systemImage: "link",
                    description: Text("That linked pair is no longer available.")
                )
            }
        }
        .navigationTitle("Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
