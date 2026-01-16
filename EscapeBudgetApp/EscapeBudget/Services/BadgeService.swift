import Foundation
import Combine
import SwiftData

struct Badge: Identifiable, Hashable {
    enum TintRole: String, Codable, Hashable {
        case tint
        case success
        case warning
        case purple
    }

    enum Collection: String, Codable, CaseIterable, Identifiable, Hashable {
        case momentum
        case onboarding
        case importing
        case budgeting
        case organizing
        case automation
        case planning
        case security

        var id: String { rawValue }

        var title: String {
            switch self {
            case .momentum: return "Momentum"
            case .onboarding: return "Getting Started"
            case .importing: return "Importing"
            case .budgeting: return "Budgeting"
            case .organizing: return "Organizing"
            case .automation: return "Automation"
            case .planning: return "Planning"
            case .security: return "Privacy & Security"
            }
        }

        var systemImage: String {
            switch self {
            case .momentum: return "flame.fill"
            case .onboarding: return "sparkles"
            case .importing: return "tray.and.arrow.down.fill"
            case .budgeting: return "chart.pie.fill"
            case .organizing: return "tag.fill"
            case .automation: return "bolt.fill"
            case .planning: return "target"
            case .security: return "lock.fill"
            }
        }
    }

    let id: String
    let collection: Collection
    let title: String
    let subtitle: String
    let systemImage: String
    let tintRole: TintRole
}

@MainActor
final class BadgeService: ObservableObject {
    static let shared = BadgeService()

    private let defaults: UserDefaults

    static let catalog: [Badge] = [
        Badge(id: "first_open", collection: .onboarding, title: "First Launch", subtitle: "Opened the app", systemImage: "sparkles", tintRole: .tint),

        Badge(id: "weekly_streak_2", collection: .momentum, title: "2‑Week Streak", subtitle: "Keep the momentum going", systemImage: "flame.fill", tintRole: .warning),
        Badge(id: "weekly_streak_4", collection: .momentum, title: "4‑Week Streak", subtitle: "Consistency is compounding", systemImage: "flame.circle.fill", tintRole: .warning),
        Badge(id: "weekly_streak_8", collection: .momentum, title: "8‑Week Streak", subtitle: "Habits unlocked", systemImage: "flame.circle.fill", tintRole: .warning),
        Badge(id: "weekly_streak_12", collection: .momentum, title: "12‑Week Streak", subtitle: "You’re building something real", systemImage: "flame.circle.fill", tintRole: .warning),
        Badge(id: "weekly_streak_24", collection: .momentum, title: "24‑Week Streak", subtitle: "Legendary consistency", systemImage: "crown.fill", tintRole: .warning),

        Badge(id: "budget_setup", collection: .budgeting, title: "Budget Set Up", subtitle: "Built your plan", systemImage: "chart.pie.fill", tintRole: .success),
        Badge(id: "budget_builder", collection: .budgeting, title: "Budget Builder", subtitle: "Created 10+ budget categories", systemImage: "square.grid.3x3.fill", tintRole: .success),
        Badge(id: "budget_consistency", collection: .budgeting, title: "On Budget (Mostly)", subtitle: "Stayed under budget for 6 months", systemImage: "checkmark.seal.fill", tintRole: .success),

        Badge(id: "import_1", collection: .importing, title: "First Import", subtitle: "Brought in your data", systemImage: "tray.and.arrow.down.fill", tintRole: .tint),
        Badge(id: "import_3", collection: .importing, title: "Importer", subtitle: "Completed 3 imports", systemImage: "tray.and.arrow.down.fill", tintRole: .tint),
        Badge(id: "import_10", collection: .importing, title: "Import Pro", subtitle: "Completed 10 imports", systemImage: "tray.and.arrow.down.fill", tintRole: .tint),
        Badge(id: "import_25", collection: .importing, title: "Import Legend", subtitle: "Completed 25 imports", systemImage: "tray.full.fill", tintRole: .tint),

        Badge(id: "tx_100", collection: .organizing, title: "Getting Organized", subtitle: "Tracked 100 transactions", systemImage: "list.bullet.rectangle", tintRole: .purple),
        Badge(id: "tx_500", collection: .organizing, title: "Serious Tracker", subtitle: "Tracked 500 transactions", systemImage: "list.bullet.rectangle.portrait", tintRole: .purple),
        Badge(id: "tx_2000", collection: .organizing, title: "Data Dynamo", subtitle: "Tracked 2,000 transactions", systemImage: "list.number", tintRole: .purple),

        Badge(id: "categorized_50", collection: .organizing, title: "Categorizer", subtitle: "Categorized 50 transactions", systemImage: "tag.fill", tintRole: .success),
        Badge(id: "categorized_250", collection: .organizing, title: "Category Master", subtitle: "Categorized 250 transactions", systemImage: "tag.circle.fill", tintRole: .success),
        Badge(id: "categorized_1000", collection: .organizing, title: "Category Wizard", subtitle: "Categorized 1,000 transactions", systemImage: "wand.and.stars", tintRole: .success),

        Badge(id: "transfers_10", collection: .organizing, title: "Transfer Tamer", subtitle: "Linked 10 transfers", systemImage: "arrow.left.arrow.right", tintRole: .tint),
        Badge(id: "transfers_50", collection: .organizing, title: "Transfer Whisperer", subtitle: "Linked 50 transfers", systemImage: "arrow.left.arrow.right.circle.fill", tintRole: .tint),

        Badge(id: "rules_1", collection: .automation, title: "Automation Starter", subtitle: "Created your first rule", systemImage: "bolt.fill", tintRole: .purple),
        Badge(id: "rules_5", collection: .automation, title: "Automation Architect", subtitle: "Created 5 rules", systemImage: "bolt.circle.fill", tintRole: .purple),

        Badge(id: "tags_5", collection: .organizing, title: "Tag Collector", subtitle: "Created 5 tags", systemImage: "tag.square.fill", tintRole: .success),
        Badge(id: "tags_15", collection: .organizing, title: "Tag Curator", subtitle: "Created 15 tags", systemImage: "tag.square.fill", tintRole: .success),

        Badge(id: "savings_goal_1", collection: .planning, title: "Goal Setter", subtitle: "Created a savings goal", systemImage: "target", tintRole: .success),
        Badge(id: "savings_goal_3", collection: .planning, title: "Goal Portfolio", subtitle: "Created 3 savings goals", systemImage: "target", tintRole: .success),
        Badge(id: "savings_goal_achieved", collection: .planning, title: "Goal Achieved", subtitle: "Completed a savings goal", systemImage: "trophy.fill", tintRole: .success),

        Badge(id: "retirement_ready", collection: .planning, title: "Retirement Ready", subtitle: "Set up your retirement plan", systemImage: "leaf.fill", tintRole: .success),
        Badge(id: "year_end_ready", collection: .planning, title: "Year In Review", subtitle: "Tracked spending across years", systemImage: "sparkles.square.filled.on.square", tintRole: .tint),

        Badge(id: "auto_backup_ready", collection: .security, title: "Safety Net", subtitle: "Set up auto-backups", systemImage: "lock.shield.fill", tintRole: .tint)
    ]

    @Published private(set) var weeklyOpenStreak: Int
    @Published private(set) var bestWeeklyOpenStreak: Int
    @Published private(set) var totalActiveWeeks: Int
    @Published private(set) var importsCompleted: Int
    @Published private(set) var lastActiveWeekStart: Date?
    @Published private(set) var earnedBadgeIDs: Set<String>

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.weeklyOpenStreak = defaults.integer(forKey: Keys.weeklyOpenStreak)
        self.bestWeeklyOpenStreak = defaults.integer(forKey: Keys.bestWeeklyOpenStreak)
        self.totalActiveWeeks = defaults.integer(forKey: Keys.totalActiveWeeks)
        self.importsCompleted = defaults.integer(forKey: Keys.importsCompleted)
        self.lastActiveWeekStart = defaults.object(forKey: Keys.lastActiveWeekStart) as? Date
        self.earnedBadgeIDs = Set((defaults.array(forKey: Keys.earnedBadges) as? [String]) ?? [])
    }

    func isEarned(_ badgeID: String) -> Bool {
        earnedBadgeIDs.contains(badgeID)
    }

    func recordAppBecameActive(modelContext: ModelContext?, now: Date = Date()) {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)

        if let lastActiveWeekStart {
            let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastActiveWeekStart)?.start ?? lastActiveWeekStart
            if lastWeek == weekStart {
                evaluateAchievements(modelContext: modelContext)
                return
            }

            let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            if lastWeek == previousWeek {
                weeklyOpenStreak += 1
            } else {
                weeklyOpenStreak = 1
            }
        } else {
            weeklyOpenStreak = max(1, weeklyOpenStreak)
        }

        lastActiveWeekStart = weekStart
        totalActiveWeeks += 1
        bestWeeklyOpenStreak = max(bestWeeklyOpenStreak, weeklyOpenStreak)

        persist()
        evaluateAchievements(modelContext: modelContext)
    }

    func recordImportCompleted(modelContext: ModelContext?) {
        importsCompleted += 1
        defaults.set(importsCompleted, forKey: Keys.importsCompleted)
        evaluateAchievements(modelContext: modelContext)
    }

    func resetAll() {
        weeklyOpenStreak = 0
        bestWeeklyOpenStreak = 0
        totalActiveWeeks = 0
        importsCompleted = 0
        lastActiveWeekStart = nil
        earnedBadgeIDs = []

        defaults.removeObject(forKey: Keys.weeklyOpenStreak)
        defaults.removeObject(forKey: Keys.bestWeeklyOpenStreak)
        defaults.removeObject(forKey: Keys.totalActiveWeeks)
        defaults.removeObject(forKey: Keys.importsCompleted)
        defaults.removeObject(forKey: Keys.lastActiveWeekStart)
        defaults.removeObject(forKey: Keys.earnedBadges)
    }

    private func persist() {
        defaults.set(weeklyOpenStreak, forKey: Keys.weeklyOpenStreak)
        defaults.set(bestWeeklyOpenStreak, forKey: Keys.bestWeeklyOpenStreak)
        defaults.set(totalActiveWeeks, forKey: Keys.totalActiveWeeks)
        defaults.set(lastActiveWeekStart, forKey: Keys.lastActiveWeekStart)
        defaults.set(Array(earnedBadgeIDs).sorted(), forKey: Keys.earnedBadges)
    }

    private func evaluateAchievements(modelContext: ModelContext?) {
        guard let modelContext else {
            // Still allow streak/import-only badges without DB access.
            awardIfEligible(
                badgeID: "first_open",
                title: "First Launch",
                subtitle: "Opened the app",
                isEligible: totalActiveWeeks >= 1,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "weekly_streak_2",
                title: "2‑Week Streak",
                subtitle: "Keep the momentum going",
                isEligible: bestWeeklyOpenStreak >= 2,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "weekly_streak_4",
                title: "4‑Week Streak",
                subtitle: "Consistency is compounding",
                isEligible: bestWeeklyOpenStreak >= 4,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "weekly_streak_8",
                title: "8‑Week Streak",
                subtitle: "Habits unlocked",
                isEligible: bestWeeklyOpenStreak >= 8,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "weekly_streak_12",
                title: "12‑Week Streak",
                subtitle: "You’re building something real",
                isEligible: bestWeeklyOpenStreak >= 12,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "weekly_streak_24",
                title: "24‑Week Streak",
                subtitle: "Legendary consistency",
                isEligible: bestWeeklyOpenStreak >= 24,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "import_1",
                title: "First Import",
                subtitle: "Brought in your data",
                isEligible: importsCompleted >= 1,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "import_3",
                title: "Importer",
                subtitle: "Completed 3 imports",
                isEligible: importsCompleted >= 3,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "import_10",
                title: "Import Pro",
                subtitle: "Completed 10 imports",
                isEligible: importsCompleted >= 10,
                modelContext: nil
            )
            awardIfEligible(
                badgeID: "import_25",
                title: "Import Legend",
                subtitle: "Completed 25 imports",
                isEligible: importsCompleted >= 25,
                modelContext: nil
            )
            return
        }

        awardIfEligible(badgeID: "first_open", title: "First Launch", subtitle: "Opened the app", isEligible: totalActiveWeeks >= 1, modelContext: modelContext)
        awardIfEligible(badgeID: "weekly_streak_2", title: "2‑Week Streak", subtitle: "Keep the momentum going", isEligible: bestWeeklyOpenStreak >= 2, modelContext: modelContext)
        awardIfEligible(badgeID: "weekly_streak_4", title: "4‑Week Streak", subtitle: "Consistency is compounding", isEligible: bestWeeklyOpenStreak >= 4, modelContext: modelContext)
        awardIfEligible(badgeID: "weekly_streak_8", title: "8‑Week Streak", subtitle: "Habits unlocked", isEligible: bestWeeklyOpenStreak >= 8, modelContext: modelContext)
        awardIfEligible(badgeID: "weekly_streak_12", title: "12‑Week Streak", subtitle: "You’re building something real", isEligible: bestWeeklyOpenStreak >= 12, modelContext: modelContext)
        awardIfEligible(badgeID: "weekly_streak_24", title: "24‑Week Streak", subtitle: "Legendary consistency", isEligible: bestWeeklyOpenStreak >= 24, modelContext: modelContext)

        awardIfEligible(badgeID: "import_1", title: "First Import", subtitle: "Brought in your data", isEligible: importsCompleted >= 1, modelContext: modelContext)
        awardIfEligible(badgeID: "import_3", title: "Importer", subtitle: "Completed 3 imports", isEligible: importsCompleted >= 3, modelContext: modelContext)
        awardIfEligible(badgeID: "import_10", title: "Import Pro", subtitle: "Completed 10 imports", isEligible: importsCompleted >= 10, modelContext: modelContext)
        awardIfEligible(badgeID: "import_25", title: "Import Legend", subtitle: "Completed 25 imports", isEligible: importsCompleted >= 25, modelContext: modelContext)

        awardIfEligible(
            badgeID: "budget_setup",
            title: "Budget Set Up",
            subtitle: "Built your plan",
            isEligible: hasBudget(modelContext: modelContext),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "budget_builder",
            title: "Budget Builder",
            subtitle: "Created 10+ budget categories",
            isEligible: hasAtLeastBudgetCategories(modelContext: modelContext, minCount: 10),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "budget_consistency",
            title: "On Budget (Mostly)",
            subtitle: "Stayed under budget for 6 months",
            isEligible: hasUnderBudgetMonths(modelContext: modelContext, minMonths: 6),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "tx_100",
            title: "Getting Organized",
            subtitle: "Tracked 100 transactions",
            isEligible: hasAtLeastTransactions(modelContext: modelContext, minCount: 100),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "tx_500",
            title: "Serious Tracker",
            subtitle: "Tracked 500 transactions",
            isEligible: hasAtLeastTransactions(modelContext: modelContext, minCount: 500),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "tx_2000",
            title: "Data Dynamo",
            subtitle: "Tracked 2,000 transactions",
            isEligible: hasAtLeastTransactions(modelContext: modelContext, minCount: 2000),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "categorized_50",
            title: "Categorizer",
            subtitle: "Categorized 50 transactions",
            isEligible: hasAtLeastCategorizedStandardTransactions(modelContext: modelContext, minCount: 50),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "categorized_250",
            title: "Category Master",
            subtitle: "Categorized 250 transactions",
            isEligible: hasAtLeastCategorizedStandardTransactions(modelContext: modelContext, minCount: 250),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "categorized_1000",
            title: "Category Wizard",
            subtitle: "Categorized 1,000 transactions",
            isEligible: hasAtLeastCategorizedStandardTransactions(modelContext: modelContext, minCount: 1000),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "transfers_10",
            title: "Transfer Tamer",
            subtitle: "Linked 10 transfers",
            isEligible: hasAtLeastLinkedTransfers(modelContext: modelContext, minPairs: 10),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "transfers_50",
            title: "Transfer Whisperer",
            subtitle: "Linked 50 transfers",
            isEligible: hasAtLeastLinkedTransfers(modelContext: modelContext, minPairs: 50),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "rules_1",
            title: "Automation Starter",
            subtitle: "Created your first rule",
            isEligible: hasAtLeastRules(modelContext: modelContext, minCount: 1),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "rules_5",
            title: "Automation Architect",
            subtitle: "Created 5 rules",
            isEligible: hasAtLeastRules(modelContext: modelContext, minCount: 5),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "tags_5",
            title: "Tag Collector",
            subtitle: "Created 5 tags",
            isEligible: hasAtLeastTags(modelContext: modelContext, minCount: 5),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "tags_15",
            title: "Tag Curator",
            subtitle: "Created 15 tags",
            isEligible: hasAtLeastTags(modelContext: modelContext, minCount: 15),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "savings_goal_1",
            title: "Goal Setter",
            subtitle: "Created a savings goal",
            isEligible: hasAtLeastSavingsGoals(modelContext: modelContext, minCount: 1),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "savings_goal_3",
            title: "Goal Portfolio",
            subtitle: "Created 3 savings goals",
            isEligible: hasAtLeastSavingsGoals(modelContext: modelContext, minCount: 3),
            modelContext: modelContext
        )
        awardIfEligible(
            badgeID: "savings_goal_achieved",
            title: "Goal Achieved",
            subtitle: "Completed a savings goal",
            isEligible: hasAchievedSavingsGoal(modelContext: modelContext),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "retirement_ready",
            title: "Retirement Ready",
            subtitle: "Set up your retirement plan",
            isEligible: defaults.object(forKey: "retirement.isConfigured") as? Bool ?? false,
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "year_end_ready",
            title: "Year In Review",
            subtitle: "Tracked spending across years",
            isEligible: hasTransactionsAcrossYears(modelContext: modelContext),
            modelContext: modelContext
        )

        awardIfEligible(
            badgeID: "auto_backup_ready",
            title: "Safety Net",
            subtitle: "Set up auto-backups",
            isEligible: AutoBackupService.isEnabled && AutoBackupService.destinationDisplayName() != nil,
            modelContext: modelContext
        )
    }

    private func awardIfEligible(
        badgeID: String,
        title: String,
        subtitle: String,
        isEligible: Bool,
        modelContext: ModelContext?
    ) {
        guard isEligible else { return }
        guard !earnedBadgeIDs.contains(badgeID) else { return }

        earnedBadgeIDs.insert(badgeID)
        persist()

        guard let modelContext else { return }

        InAppNotificationService.post(
            title: "Badge Earned",
            message: "You earned “\(title)”. \(subtitle)",
            type: .success,
            in: modelContext,
            topic: .badgeAchievements,
            dedupeKey: "badge.earned.\(badgeID)"
        )
    }

    private func hasBudget(modelContext: ModelContext) -> Bool {
        let expenseRaw = CategoryGroupType.expense.rawValue
        var descriptor = FetchDescriptor<CategoryGroup>(
            predicate: #Predicate { group in
                group.typeRawValue == expenseRaw && group.isDemoData == false
            }
        )
        descriptor.fetchLimit = 1
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return !result.isEmpty
    }

    private func hasAtLeastTransactions(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false
            }
        )
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAtLeastCategorizedStandardTransactions(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        let standardRaw = TransactionKind.standard.rawValue
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false && tx.kindRawValue == standardRaw && tx.category != nil
            }
        )
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAtLeastBudgetCategories(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { category in
                category.isDemoData == false
            }
        )
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAtLeastTags(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        var descriptor = FetchDescriptor<TransactionTag>(
            predicate: #Predicate { tag in
                tag.isDemoData == false
            }
        )
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAtLeastRules(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        var descriptor = FetchDescriptor<AutoRule>()
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAtLeastSavingsGoals(modelContext: ModelContext, minCount: Int) -> Bool {
        guard minCount > 0 else { return true }
        var descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { goal in
                goal.isDemoData == false
            }
        )
        descriptor.fetchLimit = minCount
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return result.count >= minCount
    }

    private func hasAchievedSavingsGoal(modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { goal in
                goal.isDemoData == false && goal.isAchieved == true
            }
        )
        descriptor.fetchLimit = 1
        let result = (try? modelContext.fetch(descriptor)) ?? []
        return !result.isEmpty
    }

    private func hasTransactionsAcrossYears(modelContext: ModelContext) -> Bool {
        var newest = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        newest.fetchLimit = 1
        let newestTx = (try? modelContext.fetch(newest))?.first

        var oldest = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        oldest.fetchLimit = 1
        let oldestTx = (try? modelContext.fetch(oldest))?.first

        guard let newestDate = newestTx?.date, let oldestDate = oldestTx?.date else { return false }
        let newestYear = Calendar.current.component(.year, from: newestDate)
        let oldestYear = Calendar.current.component(.year, from: oldestDate)
        return newestYear >= oldestYear + 1
    }

    private func hasAtLeastLinkedTransfers(modelContext: ModelContext, minPairs: Int) -> Bool {
        guard minPairs > 0 else { return true }
        let transferRaw = TransactionKind.transfer.rawValue
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false && tx.kindRawValue == transferRaw && tx.transferID != nil
            }
        )
        descriptor.fetchLimit = max(200, minPairs * 6)
        let result = (try? modelContext.fetch(descriptor)) ?? []
        let unique = Set(result.compactMap(\.transferID))
        return unique.count >= minPairs
    }

    private func hasUnderBudgetMonths(modelContext: ModelContext, minMonths: Int) -> Bool {
        guard minMonths > 0 else { return true }

        let expenseRaw = CategoryGroupType.expense.rawValue
        let groups: [CategoryGroup] = {
            var descriptor = FetchDescriptor<CategoryGroup>(
                predicate: #Predicate { group in
                    group.isDemoData == false && group.typeRawValue == expenseRaw
                }
            )
            descriptor.fetchLimit = 50
            return (try? modelContext.fetch(descriptor)) ?? []
        }()

        let categories = groups.flatMap { $0.categories ?? [] }
        let monthlyBudget = categories.reduce(Decimal(0)) { $0 + max(0, $1.assigned) }
        guard monthlyBudget > 0 else { return false }

        let standardRaw = TransactionKind.standard.rawValue
        var txDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.isDemoData == false && tx.kindRawValue == standardRaw && tx.amount < 0
            }
        )
        txDescriptor.fetchLimit = 5000
        let txs = (try? modelContext.fetch(txDescriptor)) ?? []

        let calendar = Calendar.current
        var byMonth: [Date: Decimal] = [:]
        for tx in txs {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            byMonth[monthStart, default: 0] += (-tx.amount)
        }

        let underCount = byMonth.values.filter { $0 <= monthlyBudget }.count
        return underCount >= minMonths
    }

    private enum Keys {
        static let weeklyOpenStreak = "badges.streak.weeklyOpen"
        static let bestWeeklyOpenStreak = "badges.streak.weeklyOpen.best"
        static let totalActiveWeeks = "badges.weeksActive.total"
        static let importsCompleted = "badges.imports.completed"
        static let lastActiveWeekStart = "badges.lastActiveWeekStart"
        static let earnedBadges = "badges.earned"
    }
}
