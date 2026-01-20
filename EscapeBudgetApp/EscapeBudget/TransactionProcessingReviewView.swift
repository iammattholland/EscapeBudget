import SwiftUI
import SwiftData

struct TransactionProcessingReviewView: View {
    let transaction: Transaction
    let events: [TransactionProcessor.Event]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TransactionRowView(transaction: transaction)
                }

                Section("Updates") {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            HStack(spacing: AppTheme.Spacing.compact) {
                                Image(systemName: iconName(for: event.kind))
                                    .foregroundStyle(AppColors.tint(for: appColorMode))
                                Text(event.title)
                                    .appSecondaryBodyText()
                            }

                            if let detail = event.detail, !detail.isEmpty {
                                Text(detail)
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, AppTheme.Spacing.indentSmall)
                            }
                        }
                    }
                }

                Section {
                    Text("Import behaviors are selected during import (you can also set them as defaults from that screen).")
                        .appFootnoteText()
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Auto Updates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func iconName(for kind: TransactionProcessor.EventKind) -> String {
        switch kind {
        case .payeeNormalized:
            return "wand.and.stars"
        case .ruleApplied:
            return "bolt.badge.checkmark"
        case .categoryChanged:
            return "tag"
        case .tagsChanged:
            return "tag.fill"
        case .memoChanged:
            return "note.text"
        case .statusChanged:
            return "checkmark.circle"
        case .transferSuggestion:
            return "arrow.left.arrow.right"
        case .invariantFix:
            return "checkmark.shield"
        }
    }
}
