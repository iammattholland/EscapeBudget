import SwiftUI
import SwiftData
import Combine

/// Central navigation coordinator for the entire app
/// Views observe these @Published properties and present their own sheet content
class AppNavigator: ObservableObject {

    // MARK: - Sheet State

    /// Transaction sheets
    @Published var showingAddTransaction = false
    @Published var showingImportTransactions = false
    @Published var showingUncategorizedTransactions = false
    @Published var editingTransaction: Transaction?

    /// Account for import flow
    @Published var selectedAccountForImport: Account?

    /// Other sheets
    @Published var showingSettings = false
    @Published var showingReports = false

    // MARK: - Root Navigation State

    /// Root tab selection (iPhone TabView / iPad sidebar)
    @Published var selectedTab: AppTab = .home

    /// Manage segmented selection (Transactions/Budget/Accounts)
    @Published var manageSelectedSection: ManageSection = .transactions

    // MARK: - Actions

    /// Present add transaction sheet
    func addTransaction() {
        showingAddTransaction = true
    }

    /// Present edit transaction sheet
    func editTransaction(_ transaction: Transaction) {
        editingTransaction = transaction
    }

    /// Present import flow
    func importTransactions(for account: Account) {
        selectedAccountForImport = account
        showingImportTransactions = true
    }

    /// Present uncategorized transactions
    func showUncategorized() {
        showingUncategorizedTransactions = true
    }

    /// Dismiss all sheets
    func dismissAll() {
        showingAddTransaction = false
        showingImportTransactions = false
        showingUncategorizedTransactions = false
        showingSettings = false
        showingReports = false
        editingTransaction = nil
    }
}
