import SwiftUI

/// Reusable operation progress state for tracking long-running operations
struct OperationProgressState: Equatable {
    enum Phase: String {
        case preparing = "Preparing"
        case processing = "Processing"
        case saving = "Saving"
        case validating = "Validating"
        case completing = "Completing"
        case custom

        var defaultMessage: String {
            "\(rawValue)…"
        }
    }

    var title: String
    var phase: Phase
    var message: String
    var current: Int?
    var total: Int?
    var cancellable: Bool

    init(title: String, phase: Phase, message: String? = nil, current: Int? = nil, total: Int? = nil, cancellable: Bool = true) {
        self.title = title
        self.phase = phase
        self.message = message ?? phase.defaultMessage
        self.current = current
        self.total = total
        self.cancellable = cancellable
    }
}

/// Reusable progress overlay view matching ImportDataView style
struct OperationProgressOverlay: View {
    let progress: OperationProgressState
    let onCancel: (() -> Void)?

    private var fractionComplete: Double? {
        guard let total = progress.total, total > 0,
              let current = progress.current else {
            return nil
        }
        return Double(current) / Double(total)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.large) {
                VStack(alignment: .leading, spacing: 10) {
                    if let fractionComplete {
                        ProgressView(value: fractionComplete)
                    } else {
                        ProgressView()
                    }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.title)
                                .appSectionTitleText()
                            Text(progress.message)
                                .appSecondaryBodyText()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let current = progress.current, let total = progress.total {
                            Text("\(current) / \(total)")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(AppTheme.Radius.compact)

                if progress.cancellable, let onCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .appSecondaryCTA()
                }
            }
            .padding()
            .frame(maxWidth: 400)
        }
    }
}

/// View modifier to show operation progress overlay
struct OperationProgressModifier: ViewModifier {
    let progress: OperationProgressState?
    let onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress {
                    OperationProgressOverlay(progress: progress, onCancel: onCancel)
                }
            }
    }
}

extension View {
    /// Shows an operation progress overlay when progress state is provided
    func operationProgress(_ progress: OperationProgressState?, onCancel: (() -> Void)? = nil) -> some View {
        modifier(OperationProgressModifier(progress: progress, onCancel: onCancel))
    }
}
