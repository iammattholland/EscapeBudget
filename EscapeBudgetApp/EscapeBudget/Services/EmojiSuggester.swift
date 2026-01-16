import Foundation

enum EmojiSuggester {
    private struct Rule {
        let keywords: [String]
        let emoji: String
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["grocer", "grocery", "supermarket", "food", "restaurant", "dining", "takeout"], emoji: "🛒"),
        Rule(keywords: ["coffee", "cafe", "espresso"], emoji: "☕️"),
        Rule(keywords: ["rent", "mortgage", "housing", "home"], emoji: "🏠"),
        Rule(keywords: ["utilities", "hydro", "electric", "power"], emoji: "💡"),
        Rule(keywords: ["internet", "wifi", "wi-fi"], emoji: "📶"),
        Rule(keywords: ["phone", "cell", "mobile"], emoji: "📱"),
        Rule(keywords: ["insurance"], emoji: "🛡️"),
        Rule(keywords: ["car", "auto", "vehicle", "parking"], emoji: "🚗"),
        Rule(keywords: ["gas", "fuel", "petrol"], emoji: "⛽️"),
        Rule(keywords: ["transit", "bus", "train", "subway", "uber", "lyft", "taxi"], emoji: "🚇"),
        Rule(keywords: ["travel", "vacation", "flight", "hotel", "airbnb"], emoji: "✈️"),
        Rule(keywords: ["health", "medical", "doctor", "clinic"], emoji: "🩺"),
        Rule(keywords: ["dental", "dentist"], emoji: "🦷"),
        Rule(keywords: ["pharmacy", "medicine", "drug"], emoji: "💊"),
        Rule(keywords: ["gym", "fitness", "workout", "exercise"], emoji: "🏋️"),
        Rule(keywords: ["child", "kids", "daycare", "baby"], emoji: "👶"),
        Rule(keywords: ["pet", "dog", "cat", "vet"], emoji: "🐾"),
        Rule(keywords: ["subscription", "netflix", "spotify", "disney"], emoji: "📺"),
        Rule(keywords: ["movie", "cinema"], emoji: "🎬"),
        Rule(keywords: ["games", "gaming"], emoji: "🎮"),
        Rule(keywords: ["education", "school", "tuition", "course"], emoji: "🎓"),
        Rule(keywords: ["gift", "birthday", "present"], emoji: "🎁"),
        Rule(keywords: ["charity", "donation"], emoji: "🤝"),
        Rule(keywords: ["salary", "payroll", "paycheck", "income", "wages"], emoji: "💰"),
        Rule(keywords: ["tax", "cra"], emoji: "🧾"),
        Rule(keywords: ["bank", "fees"], emoji: "🏦"),
        Rule(keywords: ["credit card", "creditcard", "cc"], emoji: "💳"),
        Rule(keywords: ["invest", "investing", "brokerage", "stocks", "etf"], emoji: "📈"),
        Rule(keywords: ["saving", "savings"], emoji: "💰"),
        Rule(keywords: ["repairs", "maintenance", "tools"], emoji: "🛠️")
    ]

    static func suggest(for input: String, limit: Int = 10) -> [String] {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return [] }

        var results: [String] = []
        results.reserveCapacity(limit)

        for rule in rules {
            if rule.keywords.contains(where: { normalized.contains($0) }) {
                if !results.contains(rule.emoji) {
                    results.append(rule.emoji)
                    if results.count >= limit { break }
                }
            }
        }

        return results
    }

    static func matchesCategoryTitle(_ query: String, title: String) -> Bool {
        let q = normalize(query)
        let t = normalize(title)
        guard !q.isEmpty else { return true }
        if t.contains(q) { return true }

        // Lightweight synonyms so searching "car" still surfaces "Transport", etc.
        let synonyms: [String: [String]] = [
            "transport": ["car", "auto", "vehicle", "gas", "fuel", "transit", "uber", "taxi", "train", "bus", "flight"],
            "food": ["grocery", "groceries", "restaurant", "dining", "coffee"],
            "home": ["rent", "mortgage", "utilities", "repair", "maintenance"],
            "health": ["medical", "pharmacy", "dentist", "gym", "fitness"],
            "shopping": ["clothes", "amazon", "store", "gift"]
        ]

        for (key, words) in synonyms {
            if t.contains(key), words.contains(where: { q.contains($0) }) {
                return true
            }
        }

        return false
    }

    private static func normalize(_ input: String) -> String {
        let lower = input.lowercased()
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(String(scalar))
            }
            return " "
        }
        return String(allowed)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

