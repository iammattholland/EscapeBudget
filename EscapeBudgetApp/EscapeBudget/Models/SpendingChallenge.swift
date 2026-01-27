import Foundation
import SwiftData

/// Types of spending challenges available
enum ChallengeType: String, Codable, CaseIterable, Identifiable {
    case noSpendDay = "no_spend_day"
    case noSpendWeekend = "no_spend_weekend"
    case coffeeShopFast = "coffee_shop_fast"
    case restaurantReduction = "restaurant_reduction"
    case groceryBudgetHero = "grocery_budget_hero"
    case underBudgetStreak = "under_budget_streak"
    case packLunchWeek = "pack_lunch_week"
    case entertainmentDiet = "entertainment_diet"
    case categoryFreeze = "category_freeze"
    case weeklySpendingLimit = "weekly_spending_limit"
    case savingsStreak = "savings_streak"
    case noImpulseBuys = "no_impulse_buys"
    case custom = "custom"

    var id: String { rawValue }

    /// Preset challenges only (excludes custom for Browse tab)
    static var presets: [ChallengeType] {
        allCases.filter { $0 != .custom }
    }

    var title: String {
        switch self {
        case .noSpendDay: return "No-Spend Day"
        case .noSpendWeekend: return "No-Spend Weekend"
        case .coffeeShopFast: return "Coffee Shop Fast"
        case .restaurantReduction: return "Restaurant Reduction"
        case .groceryBudgetHero: return "Grocery Budget Hero"
        case .underBudgetStreak: return "Under Budget Streak"
        case .packLunchWeek: return "Pack Lunch Week"
        case .entertainmentDiet: return "Entertainment Diet"
        case .categoryFreeze: return "Category Freeze"
        case .weeklySpendingLimit: return "Weekly Spending Cap"
        case .savingsStreak: return "Savings Streak"
        case .noImpulseBuys: return "Mindful Spending"
        case .custom: return "Custom Challenge"
        }
    }

    var description: String {
        switch self {
        case .noSpendDay:
            return "Complete a full day with zero discretionary spending."
        case .noSpendWeekend:
            return "Make it through Saturday and Sunday without spending."
        case .coffeeShopFast:
            return "Avoid coffee shop purchases for a set number of days."
        case .restaurantReduction:
            return "Cut your restaurant spending by 50% compared to last month."
        case .groceryBudgetHero:
            return "Stay within your grocery budget for the entire month."
        case .underBudgetStreak:
            return "Keep your daily spending under budget for consecutive days."
        case .packLunchWeek:
            return "No lunch purchases on weekdays for a full work week."
        case .entertainmentDiet:
            return "Cap your entertainment spending at a set limit this month."
        case .categoryFreeze:
            return "Zero spending in a chosen category for a set period."
        case .weeklySpendingLimit:
            return "Keep your total weekly discretionary spending under a limit."
        case .savingsStreak:
            return "Make transfers to savings for consecutive pay periods."
        case .noImpulseBuys:
            return "Wait 48 hours before any purchase over $50 for two weeks."
        case .custom:
            return "Your personalized spending challenge."
        }
    }

    var icon: String {
        switch self {
        case .noSpendDay: return "calendar.badge.minus"
        case .noSpendWeekend: return "moon.stars"
        case .coffeeShopFast: return "cup.and.saucer"
        case .restaurantReduction: return "fork.knife"
        case .groceryBudgetHero: return "cart"
        case .underBudgetStreak: return "flame"
        case .packLunchWeek: return "takeoutbag.and.cup.and.straw"
        case .entertainmentDiet: return "tv"
        case .categoryFreeze: return "snowflake"
        case .weeklySpendingLimit: return "dollarsign.gauge.chart.lefthalf.righthalf"
        case .savingsStreak: return "banknote"
        case .noImpulseBuys: return "brain.head.profile"
        case .custom: return "star.circle"
        }
    }

    /// Default duration in days for this challenge type
    var defaultDurationDays: Int {
        switch self {
        case .noSpendDay: return 1
        case .noSpendWeekend: return 2
        case .coffeeShopFast: return 7
        case .restaurantReduction: return 30
        case .groceryBudgetHero: return 30
        case .underBudgetStreak: return 7
        case .packLunchWeek: return 5
        case .entertainmentDiet: return 30
        case .categoryFreeze: return 14
        case .weeklySpendingLimit: return 7
        case .savingsStreak: return 30
        case .noImpulseBuys: return 14
        case .custom: return 7
        }
    }

    /// Difficulty level for display
    var difficulty: ChallengeDifficulty {
        switch self {
        case .noSpendDay: return .easy
        case .noSpendWeekend: return .medium
        case .coffeeShopFast: return .easy
        case .restaurantReduction: return .hard
        case .groceryBudgetHero: return .medium
        case .underBudgetStreak: return .medium
        case .packLunchWeek: return .medium
        case .entertainmentDiet: return .easy
        case .categoryFreeze: return .hard
        case .weeklySpendingLimit: return .medium
        case .savingsStreak: return .easy
        case .noImpulseBuys: return .hard
        case .custom: return .medium
        }
    }

    /// Categories relevant to this challenge (for filtering transactions)
    var relevantCategoryKeywords: [String] {
        switch self {
        case .coffeeShopFast:
            return ["coffee", "starbucks", "cafe", "espresso", "latte"]
        case .restaurantReduction:
            return ["restaurant", "dining", "food", "takeout", "delivery"]
        case .groceryBudgetHero:
            return ["grocery", "groceries", "supermarket", "food"]
        case .packLunchWeek:
            return ["lunch", "restaurant", "fast food", "takeout"]
        case .entertainmentDiet:
            return ["entertainment", "streaming", "movies", "games", "subscription"]
        default:
            return []
        }
    }
}

/// Filter type for custom challenges
enum CustomChallengeFilterType: String, Codable, CaseIterable, Identifiable {
    case category = "category"
    case categoryGroup = "category_group"
    case payee = "payee"
    case totalSpending = "total_spending"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: return "Category"
        case .categoryGroup: return "Budget Group"
        case .payee: return "Payee"
        case .totalSpending: return "Total Spending"
        }
    }

    var description: String {
        switch self {
        case .category: return "Limit spending in a specific category"
        case .categoryGroup: return "Limit spending across a budget group"
        case .payee: return "Limit spending at a specific merchant"
        case .totalSpending: return "Limit all discretionary spending"
        }
    }

    var icon: String {
        switch self {
        case .category: return "folder"
        case .categoryGroup: return "square.stack.3d.up"
        case .payee: return "building.2"
        case .totalSpending: return "dollarsign.circle"
        }
    }
}

enum ChallengeDifficulty: String, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var color: String {
        switch self {
        case .easy: return "green"
        case .medium: return "orange"
        case .hard: return "red"
        }
    }
}

enum ChallengeStatus: String, Codable {
    case available = "available"
    case active = "active"
    case completed = "completed"
    case failed = "failed"
}

@Model
final class SpendingChallenge: DemoDataTrackable {
    var id: UUID
    var typeRawValue: String
    var statusRawValue: String
    var startDate: Date
    var endDate: Date
    var targetAmount: Decimal?
    var targetCategoryName: String?
    var currentProgress: Double
    var completedDate: Date?
    var isDemoData: Bool = false

    // Custom challenge fields
    var customTitle: String?
    var customFilterTypeRawValue: String?
    var customFilterValue: String?
    var customCategoryGroupName: String?

    var type: ChallengeType {
        get { ChallengeType(rawValue: typeRawValue) ?? .noSpendDay }
        set { typeRawValue = newValue.rawValue }
    }

    var status: ChallengeStatus {
        get { ChallengeStatus(rawValue: statusRawValue) ?? .available }
        set { statusRawValue = newValue.rawValue }
    }

    var customFilterType: CustomChallengeFilterType? {
        get {
            guard let raw = customFilterTypeRawValue else { return nil }
            return CustomChallengeFilterType(rawValue: raw)
        }
        set { customFilterTypeRawValue = newValue?.rawValue }
    }

    /// Display title (uses custom title for custom challenges)
    var displayTitle: String {
        if type == .custom, let custom = customTitle, !custom.isEmpty {
            return custom
        }
        return type.title
    }

    /// Display icon (uses filter type icon for custom challenges)
    var displayIcon: String {
        if type == .custom, let filterType = customFilterType {
            return filterType.icon
        }
        return type.icon
    }

    var isActive: Bool {
        status == .active && Date() <= endDate
    }

    var isExpired: Bool {
        status == .active && Date() > endDate
    }

    var daysRemaining: Int {
        let calendar = Calendar.current
        let remaining = calendar.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(0, remaining)
    }

    var daysElapsed: Int {
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return max(0, elapsed)
    }

    var totalDays: Int {
        let calendar = Calendar.current
        let total = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(1, total + 1)
    }

    init(
        type: ChallengeType,
        startDate: Date = Date(),
        durationDays: Int? = nil,
        targetAmount: Decimal? = nil,
        targetCategoryName: String? = nil,
        isDemoData: Bool = false
    ) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let duration = durationDays ?? type.defaultDurationDays
        let end = calendar.date(byAdding: .day, value: duration - 1, to: start) ?? startDate

        self.id = UUID()
        self.typeRawValue = type.rawValue
        self.statusRawValue = ChallengeStatus.active.rawValue
        self.startDate = start
        self.endDate = end
        self.targetAmount = targetAmount
        self.targetCategoryName = targetCategoryName
        self.currentProgress = 0
        self.isDemoData = isDemoData
        self.customTitle = nil
        self.customFilterTypeRawValue = nil
        self.customFilterValue = nil
        self.customCategoryGroupName = nil
    }

    /// Creates a custom challenge with user-defined parameters
    static func createCustom(
        title: String,
        filterType: CustomChallengeFilterType,
        filterValue: String,
        targetAmount: Decimal,
        durationDays: Int,
        categoryGroupName: String? = nil,
        startDate: Date = Date()
    ) -> SpendingChallenge {
        let challenge = SpendingChallenge(
            type: .custom,
            startDate: startDate,
            durationDays: durationDays,
            targetAmount: targetAmount
        )
        challenge.customTitle = title
        challenge.customFilterType = filterType
        challenge.customFilterValue = filterValue
        challenge.customCategoryGroupName = categoryGroupName

        // Set target category name for category-based filters
        if filterType == .category {
            challenge.targetCategoryName = filterValue
        }

        return challenge
    }
}
