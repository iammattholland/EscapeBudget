import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
	    var importingView: some View {
	        VStack(spacing: AppTheme.Spacing.xLarge) {
	            if let progress = importProgress {
	                if let totalRaw = progress.total {
	                    let total = max(totalRaw, 1)
	                    let current = min(max(progress.current, 0), total)
	                    ProgressView("Importing…", value: Double(current), total: Double(total))
	                        .progressViewStyle(.circular)

		                    Text("\(current) of \(total)")
		                        .appSecondaryBodyText()
		                        .foregroundStyle(.secondary)
	                } else {
	                    ProgressView("Importing…")
	                        .progressViewStyle(.circular)
	                }
	            } else {
	                ProgressView("Importing…")
	                    .progressViewStyle(.circular)
	            }
	            
	            Text("Processed: \(importProgress?.current ?? importedCount)")
	                .appSecondaryBodyText()
	                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
		    var completeView: some View {
            ScrollView {
	            VStack(spacing: AppTheme.Spacing.xLarge) {
	                Image(systemName: "checkmark.circle.fill")
	                    .appIcon(size: 80)
	                    .foregroundStyle(AppColors.success(for: appColorMode))
                
                Text("Import Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Successfully imported \(importedCount) transactions.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)

                    if let result = importProcessingResult {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
	                            HStack {
	                                Text("What happened")
	                                    .appSectionTitleText()
	                                Spacer()
                                if result.summary.changedCount > 0 {
                                    Text("\(result.summary.changedCount) changed")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                                if result.summary.payeesNormalizedCount > 0 {
                                    summaryLine("Payees cleaned", value: "\(result.summary.payeesNormalizedCount)")
                                }
                                if result.summary.transactionsWithRulesApplied > 0 {
                                    summaryLine("Auto rules applied", value: "\(result.summary.transactionsWithRulesApplied)")
                                }
                                if result.summary.transferSuggestionsInvolvingProcessed > 0 {
                                    summaryLine("Transfer suggestions", value: "\(result.summary.transferSuggestionsInvolvingProcessed)")
                                }
	                                if result.summary.changedCount == 0 && result.summary.transferSuggestionsInvolvingProcessed == 0 {
	                                    Text("No automated changes were made.")
	                                        .appSecondaryBodyText()
	                                        .foregroundStyle(.secondary)
	                                }
                            }

                            Button {
                                showingImportProcessingReview = true
                            } label: {
                                HStack(spacing: AppTheme.Spacing.compact) {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text(result.summary.changedCount > 0 ? "Review Changes" : "Review")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(result.summary.changedCount == 0 && result.summary.transferSuggestionsInvolvingProcessed == 0)
                        }
                        .padding(AppTheme.Spacing.cardPadding)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .padding(.horizontal, AppTheme.Spacing.relaxed)
                    }
	                
	                Button("Done") {
                        navigator.selectedTab = .manage
                        navigator.manageNavigator.selectedSection = .transactions
	                    dismiss()
	                }
	                .buttonStyle(.borderedProminent)
	                .controlSize(.large)
	            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.modalVertical)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
	    func summaryLine(_ title: String, value: String) -> some View {
	        HStack {
	            Text(title)
	                .appSecondaryBodyText()
	                .foregroundStyle(.secondary)
	            Spacer()
	            Text(value)
	                .appSecondaryBodyText()
	                .fontWeight(.semibold)
	                .foregroundStyle(.secondary)
	                .monospacedDigit()
	        }
	    }

    // MARK: - Complete View
}
