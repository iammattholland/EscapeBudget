import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case manage = "Manage"
    case plan = "Plan"
    case home = "Home"
    case review = "Review"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .manage: return "slider.horizontal.3"
        case .plan: return "list.clipboard"
        case .home: return "house.fill"
        case .review: return "chart.bar.fill"
        case .tools: return "hammer"
        }
    }
}

enum ManageSection: String, CaseIterable, Identifiable {
    case transactions = "Transactions"
    case budget = "Budget"
    case accounts = "Accounts"

    var id: String { rawValue }
}

