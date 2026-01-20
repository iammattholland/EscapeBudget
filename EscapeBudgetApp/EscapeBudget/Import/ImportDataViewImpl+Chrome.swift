import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    var wizardStepIndicator: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                HStack(spacing: AppTheme.Spacing.compact) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentWizardStep.rawValue ? AppColors.tint(for: appColorMode) : Color.gray.opacity(0.3))
                            .frame(width: 26, height: 26)

                        if step.rawValue < currentWizardStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(step.rawValue <= currentWizardStep.rawValue ? .white : .gray)
                        }
                    }

                    if step == currentWizardStep {
                        Text(step.title)
                            .appSecondaryBodyText()
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: step == currentWizardStep ? .infinity : 34, alignment: .leading)
                .clipped()
                .layoutPriority(step == currentWizardStep ? 1 : 0)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: currentWizardStep)
        .padding(.horizontal)
        .padding(.vertical, AppTheme.Spacing.small)
    }
    
    func cancelBackgroundWork() {
        importTask?.cancel()
        importTask = nil
        isProcessing = false
        importProgress = nil
        if currentStep == .importing {
            currentStep = .preview
        }
    }

    func cancelImport() {
        cancelBackgroundWork()
        hasConfiguredImportOptionsThisRun = false
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
            selectedFileURL = nil
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
            encryptedExportURL = nil
        }
        dismiss()
    }

	    struct ImportProgressState: Equatable {
	        enum Phase: String {
	            case parsing = "Parsing CSV"
	            case preparing = "Preparing"
	            case saving = "Saving"
                case processing = "Processing"
	        }

        var title: String
        var phase: Phase
        var message: String
        var current: Int
        var total: Int?
        var canCancel: Bool
    }

    struct ImportProgressOverlay: View {
        let progress: ImportProgressState
        let onCancel: (() -> Void)?

        var fractionComplete: Double? {
            guard let total = progress.total, total > 0 else { return nil }
            return min(1, Double(progress.current) / Double(total))
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: AppTheme.Spacing.cardGap) {
	                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
	                        Text(progress.title)
	                            .appSectionTitleText()

	                        Text(progress.phase.rawValue)
	                            .appSecondaryBodyText()
	                            .foregroundStyle(.secondary)
	                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        if let fractionComplete {
                            ProgressView(value: fractionComplete)
                        } else {
                            ProgressView()
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(progress.message)
                                .font(AppTheme.Typography.secondaryBody)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer()

                            if let total = progress.total {
                                Text("\(min(progress.current, total)) / \(total)")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else if progress.current > 0 {
                                Text("\(progress.current)")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    if let onCancel {
                        Button("Cancel Import", role: .destructive) {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(AppTheme.Spacing.screenHorizontal)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.overlay, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.overlay, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, AppTheme.Spacing.large)
            }
        }
    }
    
    var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }
    
    var canAdvanceFromHeader: Bool {
        hasLoadedPreview && !previewRows.isEmpty
    }
    
    var canAdvanceToPreview: Bool {
        // Ensure at least Date and Amount are mapped, or other logic
        let mapped = columnMapping.values
        return mapped.contains("Date") && (mapped.contains("Amount") || (mapped.contains("Inflow") || mapped.contains("Outflow")))
    }
}
