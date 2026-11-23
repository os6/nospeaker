import SwiftUI

/// Adding an interface language only requires one case and one translated
/// Localizable.xcstrings entry per visible key.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, hungarian = "hu", english = "en"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .hungarian: "Magyar"
        case .english: "English"
        }
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

enum InterfaceTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// One palette for the entire app. Use native semantic text colors so
/// accessibility contrast and user text settings remain controlled by macOS.
enum StudioStyle {
    static let spacing: CGFloat = 20
    static let inset: CGFloat = 30
    static let sidebarWidth: CGFloat = 252
    static let cornerRadius: CGFloat = 12

    static func accentNS(for scheme: ColorScheme) -> NSColor {
        scheme == .dark ?
            NSColor(srgbRed: 0.99, green: 0.62, blue: 0.44, alpha: 1) :
            NSColor(srgbRed: 0.74, green: 0.32, blue: 0.18, alpha: 1)
    }

    static func accent(for scheme: ColorScheme) -> Color {
        Color(nsColor: accentNS(for: scheme))
    }

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ?
            Color(red: 0.105, green: 0.113, blue: 0.12) :
            Color(red: 0.976, green: 0.976, blue: 0.966)
    }

    static func sidebar(for scheme: ColorScheme) -> Color {
        scheme == .dark ?
            Color(red: 0.145, green: 0.153, blue: 0.164) :
            Color(red: 0.943, green: 0.943, blue: 0.93)
    }

    static func editor(for scheme: ColorScheme) -> Color {
        scheme == .dark ?
            Color(red: 0.125, green: 0.133, blue: 0.145) :
            Color.white
    }
}
