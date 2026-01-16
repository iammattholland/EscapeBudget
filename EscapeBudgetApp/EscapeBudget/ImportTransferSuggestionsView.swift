import SwiftUI

struct ImportTransferSuggestionsView: View {
    @Environment(\.dismiss) private var dismiss

    let currencyCode: String
    let suggestions: [ImportTransferSuggester.Suggestion]
    @Binding var selectedIDs: Set<String>
    let transactionLookup: (UUID) -> ImportedTransaction?
    let accountNameFor: (ImportedTransaction) -> String
    let onRefresh: () -> Void
    let onLinkSelected: () -> Void

    var body: some View {
        List {
            Section {
                Text("Review suggested transfer pairs before linking them. Only selected pairs will be linked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    selectedIDs = Set(suggestions.map(\.id))
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                }

                Button {
                    selectedIDs = []
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }

                Button(action: onRefresh) {
                    Label("Refresh Suggestions", systemImage: "arrow.clockwise")
                }
            }

            Section {
                Button(action: onLinkSelected) {
                    Label("Link Selected (\(selectedIDs.count))", systemImage: "link")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
            }

            Section("Suggestions") {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No Suggestions",
                        systemImage: "sparkles",
                        description: Text("Try widening your selection or refreshing after mapping accounts.")
                    )
                } else {
                    ForEach(suggestions) { suggestion in
                        let isSelected = selectedIDs.contains(suggestion.id)
                        Button {
                            if isSelected { selectedIDs.remove(suggestion.id) }
                            else { selectedIDs.insert(suggestion.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    if let outflow = transactionLookup(suggestion.outflowID),
                                       let inflow = transactionLookup(suggestion.inflowID) {
                                        Text("\(accountNameFor(outflow)) → \(accountNameFor(inflow))")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)

                                        Text("\(outflow.date.formatted(.dateTime.month(.abbreviated).day())) • \(suggestion.daysApart)d apart")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text("Transfer")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    if let outflow = transactionLookup(suggestion.outflowID) {
                                        Text(abs(outflow.amount), format: .currency(code: currencyCode))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .monospacedDigit()
                                    }
                                    Text("\(Int((suggestion.score * 100).rounded()))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Transfer Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Cancel") {
                    dismiss()
                }

                Button("Done") {
                    if !selectedIDs.isEmpty {
                        onLinkSelected()
                    }
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
