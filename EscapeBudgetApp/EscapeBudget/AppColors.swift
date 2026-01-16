import SwiftUI

enum AppColorMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case neutral = "Neutral"

    var id: String { rawValue }
}

private struct AppColorModeKey: EnvironmentKey {
    static let defaultValue: AppColorMode = .standard
}

extension EnvironmentValues {
    var appColorMode: AppColorMode {
        get { self[AppColorModeKey.self] }
        set { self[AppColorModeKey.self] = newValue }
    }
}

enum AppColors {
    static func currentModeFromDefaults() -> AppColorMode {
        let rawValue = UserDefaults.standard.string(forKey: "appColorMode") ?? AppColorMode.standard.rawValue
        return AppColorMode(rawValue: rawValue) ?? .standard
    }

    static func tint(for mode: AppColorMode) -> Color {
        switch mode {
        case .standard:
            return .blue
        case .neutral:
            // Muted slate-blue
            return Color(red: 0.34, green: 0.41, blue: 0.50)
        }
    }

    static func info(for mode: AppColorMode) -> Color {
        tint(for: mode)
    }

    static func success(for mode: AppColorMode) -> Color {
        switch mode {
        case .standard:
            return .green
        case .neutral:
            // Muted sage
            return Color(red: 0.36, green: 0.50, blue: 0.42)
        }
    }

    static func warning(for mode: AppColorMode) -> Color {
        switch mode {
        case .standard:
            return .orange
        case .neutral:
            // Muted sand / amber
            return Color(red: 0.62, green: 0.50, blue: 0.34)
        }
    }

    static func danger(for mode: AppColorMode) -> Color {
        switch mode {
        case .standard:
            return .red
        case .neutral:
            // Muted rose
            return Color(red: 0.62, green: 0.36, blue: 0.40)
        }
    }
}
