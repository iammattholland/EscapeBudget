import Foundation

enum TagColorPalette {
    static func options(for mode: AppColorMode) -> [(hex: String, name: String)] {
        switch mode {
        case .standard:
            return standardOptions
        case .neutral:
            return neutralOptions
        }
    }

    static func defaultHex(for mode: AppColorMode) -> String {
        switch mode {
        case .standard:
            return "#007AFF"
        case .neutral:
            return "#576980"
        }
    }

    static var options: [(hex: String, name: String)] {
        options(for: AppColors.currentModeFromDefaults())
    }

    static var defaultHex: String {
        defaultHex(for: AppColors.currentModeFromDefaults())
    }

    static let standardOptions: [(hex: String, name: String)] = [
        ("#007AFF", "Blue"),
        ("#34C759", "Green"),
        ("#FF3B30", "Red"),
        ("#FF9500", "Orange"),
        ("#AF52DE", "Purple"),
        ("#FF2D55", "Pink"),
        ("#5856D6", "Indigo"),
        ("#5AC8FA", "Teal"),
        ("#8E8E93", "Gray")
    ]

    static let neutralOptions: [(hex: String, name: String)] = [
        ("#576980", "Slate"),
        ("#5C806B", "Sage"),
        ("#9E8057", "Sand"),
        ("#9E5C66", "Rose"),
        ("#7C5C8A", "Plum"),
        ("#5D7A7A", "Teal Gray"),
        ("#6B7280", "Graphite"),
        ("#94A3B8", "Mist"),
        ("#8B7E74", "Mocha")
    ]
}
