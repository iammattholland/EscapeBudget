import SwiftUI

struct ReviewView: View {
    enum ReportSection: String, CaseIterable {
        case budget = "Budget"
        case income = "Income"
        case expenses = "Expenses"
        case custom = "Custom"
    }

    @State private var selectedSection: ReportSection = .budget
    @State private var sharedMonth = Date()
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isTopChromeCompact = false
    @State private var lastScrollOffset: CGFloat = 0

    private var topChromeLargeTitleClearance: CGFloat { 0 }
    private var compactThreshold: CGFloat { -80 }
    private var expandThreshold: CGFloat { -20 }

    private var activeScrollKey: String? {
        switch selectedSection {
        case .budget:
            return "BudgetPerformanceView.scroll"
        case .income:
            return "ReportsIncomeView.scroll"
        case .expenses:
            return "ReportsSpendingView.scroll"
        case .custom:
            return "CustomDashboardView.scroll"
        }
    }

    var body: some View {
        NavigationStack {
            reviewBody
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        TopChromeTabs(
                            selection: $selectedSection,
                            tabs: ReportSection.allCases.map { .init(id: $0, title: $0.rawValue) },
                            isCompact: isTopChromeCompact
                        )

                        DateRangeFilterHeader(
                            filterMode: $filterMode,
                            date: $sharedMonth,
                            customStartDate: $customStartDate,
                            customEndDate: $customEndDate,
                            isCompact: isTopChromeCompact
                        )
                        .topChromeSegmentedStyle(isCompact: isTopChromeCompact)
                    }
                    .padding(.top, topChromeLargeTitleClearance)
                    .appAdaptiveScreenHorizontalPadding()
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                }
                .onPreferenceChange(NamedScrollOffsetsPreferenceKey.self) { offsets in
                    let offset = activeScrollKey.flatMap { offsets[$0] } ?? 0
                    lastScrollOffset = offset
                    if !isTopChromeCompact, offset < compactThreshold {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isTopChromeCompact = true
                        }
                    } else if isTopChromeCompact, offset > expandThreshold {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isTopChromeCompact = false
                        }
                    }
                }
                .onChange(of: selectedSection) { _, _ in
                    isTopChromeCompact = false
                }
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
                .withAppLogo()
                .environment(\.demoPillVisible, lastScrollOffset > -20)
        }
    }

    @ViewBuilder
    private var reviewBody: some View {
        Group {
            switch selectedSection {
            case .expenses:
                ReportsSpendingView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .income:
                ReportsIncomeView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .budget:
                BudgetPerformanceView(
                    selectedDate: $sharedMonth,
                    filterMode: $filterMode,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
            case .custom:
                CustomDashboardView()
            }
        }
        .if(filterMode == .month && selectedSection != .custom) { view in
            view.monthSwipeNavigation(selectedDate: $sharedMonth)
        }
    }
}
