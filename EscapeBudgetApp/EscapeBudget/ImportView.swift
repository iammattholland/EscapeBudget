import SwiftUI
import SwiftData

/// Unified import entry point for account-driven imports.
/// This intentionally reuses `ImportDataView` so the Settings import and Account import share the same wizard.
struct ImportView: View {
    let account: Account

    var body: some View {
        ImportDataView(initialAccount: account)
    }
}

