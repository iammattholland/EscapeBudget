import SwiftUI
import SwiftData
import Combine

/// Central navigation coordinator for the entire app
/// Views observe these @Published properties and present their own sheet content
final class AppNavigator: ObservableObject {
    let manageNavigator = ManageNavigator()

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
    @Published var showingImportData = false

    // MARK: - Root Navigation State

    /// Root tab selection (iPhone TabView / iPad sidebar)
    @Published var selectedTab: AppTab = .home

    // MARK: - Deep Links

    enum ReviewSection: String, Equatable {
        case budget
        case income
        case expenses
    }

    struct ReviewDeepLink: Equatable {
        let section: ReviewSection
        let date: Date
        let filterMode: DateRangeFilterHeader.FilterMode
        let customStartDate: Date
        let customEndDate: Date
    }

    @Published var reviewDeepLink: ReviewDeepLink?

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

    /// Present import wizard (no account required)
    func importData() {
        showingImportData = true
    }

    /// Present uncategorized transactions
    func showUncategorized() {
        showingUncategorizedTransactions = true
    }

    func openReview(
        section: ReviewSection,
        date: Date = Date(),
        filterMode: DateRangeFilterHeader.FilterMode = .month,
        customStartDate: Date = Date(),
        customEndDate: Date = Date()
    ) {
        reviewDeepLink = ReviewDeepLink(
            section: section,
            date: date,
            filterMode: filterMode,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
        selectedTab = .review
    }

    /// Dismiss all sheets
    func dismissAll() {
        showingAddTransaction = false
        showingImportTransactions = false
        showingUncategorizedTransactions = false
        showingSettings = false
        showingReports = false
        showingImportData = false
        editingTransaction = nil
    }
}
