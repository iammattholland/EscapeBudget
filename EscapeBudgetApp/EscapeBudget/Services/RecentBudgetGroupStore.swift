import Foundation
import SwiftData

enum RecentBudgetGroupStore {
    private static let key = "budget.move.recentGroups"
    private static let maxEntries = 5

    struct Entry: Codable, Hashable {
        let name: String
        let typeRawValue: String
        let timestamp: Double
    }

    static func load(defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func save(_ entries: [Entry], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    static func record(group: CategoryGroup, defaults: UserDefaults = .standard) {
        let now = Date().timeIntervalSince1970
        var entries = load(defaults: defaults)
        entries.removeAll { $0.name == group.name && $0.typeRawValue == group.typeRawValue }
        entries.insert(Entry(name: group.name, typeRawValue: group.typeRawValue, timestamp: now), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries, defaults: defaults)
    }

    static func resolve(
        from categoryGroups: [CategoryGroup],
        requiredType: CategoryGroupType?
    ) -> [CategoryGroup] {
        let entries = load()
        let filtered = entries.filter { entry in
            guard let requiredType else { return true }
            return entry.typeRawValue == requiredType.rawValue
        }
        return filtered.compactMap { entry in
            categoryGroups.first { group in
                group.name == entry.name && group.typeRawValue == entry.typeRawValue
            }
        }
    }
}
