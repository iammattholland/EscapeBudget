import Foundation
import SwiftData

extension ModelContext {
    @discardableResult
    func safeSave(
        context: String,
        userTitle: String = "Error",
        userMessage: String = "Couldn't save your changes. Please try again.",
        showErrorToUser: Bool = true,
        enableRetry: Bool = false
    ) -> Bool {
        do {
            try save()
            DataChangeTracker.bump()
            return true
        } catch {
            SecurityLogger.shared.logSecurityError(error, context: context)
            if showErrorToUser {
                Task { @MainActor in
                    if enableRetry {
                        AppErrorCenter.shared.showOperation(
                            .save,
                            error: error,
                            retryAction: { [weak self] in
                                guard let self else { return }
                                _ = self.safeSave(
                                    context: context,
                                    userTitle: userTitle,
                                    userMessage: userMessage,
                                    showErrorToUser: showErrorToUser,
                                    enableRetry: enableRetry
                                )
                            }
                        )
                    } else {
                        AppErrorCenter.shared.show(title: userTitle, message: userMessage)
                    }
                }
            }
            return false
        }
    }
}
