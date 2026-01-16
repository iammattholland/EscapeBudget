import Foundation
import Combine
import SwiftUI
import SwiftData

@MainActor
final class AppErrorCenter: ObservableObject {
    static let shared = AppErrorCenter()

    struct PresentedError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let retryAction: (() -> Void)?
        let operationType: OperationType?

        init(title: String, message: String, retryAction: (() -> Void)? = nil, operationType: OperationType? = nil) {
            self.title = title
            self.message = message
            self.retryAction = retryAction
            self.operationType = operationType
        }
    }

    enum OperationType {
        case save
        case delete
        case export
        case `import`
        case sync
        case network
        case authentication
        case validation

        var userFriendlyName: String {
            switch self {
            case .save: return "saving"
            case .delete: return "deleting"
            case .export: return "exporting"
            case .`import`: return "importing"
            case .sync: return "syncing"
            case .network: return "connecting"
            case .authentication: return "authenticating"
            case .validation: return "validating"
            }
        }

        var defaultMessage: String {
            switch self {
            case .save: return "Couldn't save your changes. Please try again."
            case .delete: return "Couldn't delete the item. Please try again."
            case .export: return "Couldn't export your data. Please try again."
            case .`import`: return "Couldn't import the data. Please check the file format."
            case .sync: return "Couldn't sync your data. Please check your connection."
            case .network: return "Network error. Please check your connection and try again."
            case .authentication: return "Authentication failed. Please try again."
            case .validation: return "Please check your input and try again."
            }
        }
    }

    @Published var presentedError: PresentedError?
    private var diagnosticsModelContext: ModelContext?

    private init() {}

    func setDiagnosticsModelContext(_ modelContext: ModelContext) {
        diagnosticsModelContext = modelContext
    }

    func show(title: String = "Error", message: String, retryAction: (() -> Void)? = nil, operationType: OperationType? = nil) {
        show(title: title, message: message, retryAction: retryAction, operationType: operationType, logDiagnostics: true)
    }

    private func show(title: String, message: String, retryAction: (() -> Void)?, operationType: OperationType?, logDiagnostics: Bool) {
        if logDiagnostics, let modelContext = diagnosticsModelContext {
            DiagnosticsService.recordEvent(
                title: title,
                message: message,
                area: "ui",
                severity: .error,
                operation: operationType.map { String(describing: $0) },
                in: modelContext
            )
        }
        presentedError = PresentedError(title: title, message: message, retryAction: retryAction, operationType: operationType)
    }

    func show(_ error: Error, title: String = "Error", retryAction: (() -> Void)? = nil, operationType: OperationType? = nil) {
        let message = operationType?.defaultMessage ?? error.localizedDescription
        if let modelContext = diagnosticsModelContext {
            DiagnosticsService.recordError(
                error,
                title: title,
                message: message,
                area: "ui",
                operation: operationType.map { String(describing: $0) },
                in: modelContext
            )
        }
        show(title: title, message: message, retryAction: retryAction, operationType: operationType, logDiagnostics: false)
    }

    func showOperation(_ operation: OperationType, error: Error, retryAction: (() -> Void)? = nil) {
        let title = "Error \(operation.userFriendlyName)"
        show(error, title: title, retryAction: retryAction, operationType: operation)
    }
}
