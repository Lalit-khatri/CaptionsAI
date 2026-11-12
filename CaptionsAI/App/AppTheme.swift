import SwiftUI

// MARK: - AppTheme

/// The colour scheme of the app's own chrome: buttons, selection, progress,
/// links. Caption styles keep their own colours; this never touches what is
/// burned into a video.
///
/// Snow (white) is what ships. The others exist so the look can be
/// compared on a real screen, from the Theme switch that only Debug builds
/// show in the top-right menu.
enum AppTheme: String, CaseIterable, Identifiable {
    /// Charcoal buttons, the icon's yellow for selection.
    case midnight
    /// The original violet-to-blue.
    case violet
    /// White buttons with black text. The default.
    case snow
    case ocean
    case sunset
    case emerald

    static let `default`: AppTheme = .snow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Black"
        case .violet: return "Purple"
        case .snow: return "White"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .emerald: return "Emerald"
        }
    }

    /// Fill of primary buttons (Choose Video, Export, Get Started, the
    /// paywall's purchase button) and the progress ring, left to right.
    var gradientHex: [String] {
        switch self {
        case .midnight: return ["#3A3A3F", "#1C1C1F"]
        case .violet: return ["#7C3AED", "#3B82F6"]
        case .snow: return ["#FFFFFF", "#E4E4E9"]
        case .ocean: return ["#0A6CFF", "#2A5CE6"]
        case .sunset: return ["#E11D48", "#D9480F"]
        case .emerald: return ["#0E7C5A", "#047857"]
        }
    }

    /// Text and icons drawn on `gradient`.
    var onPrimaryHex: String {
        self == .snow ? "#000000" : "#FFFFFF"
    }

    /// Solid colour for selection: chosen chips and tabs, checkmarks, the
    /// play button, slider tint.
    var accentHex: String {
        switch self {
        case .midnight: return "#FFD60A"
        case .violet: return "#7C3AED"
        case .snow: return "#FFFFFF"
        case .ocean: return "#0A6CFF"
        case .sunset: return "#E11D48"
        case .emerald: return "#0E7C5A"
        }
    }

    /// Text and icons drawn on `accent`.
    var onAccentHex: String {
        switch self {
        case .midnight, .snow: return "#000000"
        case .violet, .ocean, .sunset, .emerald: return "#FFFFFF"
        }
    }

    /// The accent as body text on the black background. Lighter than
    /// `accent` where that one is too dark to read (violet is 3.7:1 on black,
    /// under the 4.5:1 minimum).
    var accentTextHex: String {
        switch self {
        case .midnight: return "#FFD60A"
        case .violet: return "#A78BFA"
        case .snow: return "#FFFFFF"
        case .ocean: return "#64D2FF"
        case .sunset: return "#FF9E8A"
        case .emerald: return "#6EE7B7"
        }
    }

    /// The dark wash behind onboarding and the top of the paywall.
    var backdropHex: [String] {
        switch self {
        case .midnight: return ["#18181B", "#0B0B0D"]
        case .violet: return ["#1A1040", "#0F1B3D"]
        case .snow: return ["#1C1C1E", "#0B0B0D"]
        case .ocean: return ["#0A1A33", "#07101F"]
        case .sunset: return ["#2B1215", "#160A0B"]
        case .emerald: return ["#062019", "#03110D"]
        }
    }

    /// For things drawn straight on the dark background rather than behind
    /// text: progress bars and rings, the waveform, the onboarding glyph.
    /// The same as the button gradient, except for Black, whose charcoal
    /// would vanish there; it uses the icon's yellow instead.
    var vividGradientHex: [String] {
        self == .midnight ? ["#FFD60A", "#FFB800"] : gradientHex
    }

    var gradient: [Color] { gradientHex.map { Color(hex: $0) } }
    var vividGradient: [Color] { vividGradientHex.map { Color(hex: $0) } }
    var onPrimary: Color { Color(hex: onPrimaryHex) }
    var accent: Color { Color(hex: accentHex) }
    var onAccent: Color { Color(hex: onAccentHex) }
    var accentText: Color { Color(hex: accentTextHex) }
    var backdrop: [Color] { backdropHex.map { Color(hex: $0) } }

    /// The theme in use. Read inside a view's `body`, this re-renders the
    /// view when the theme changes, because `ThemeStore` is observable.
    static var current: AppTheme { ThemeStore.shared.theme }
}

// MARK: - ThemeStore

/// Holds the chosen theme.
///
/// Release builds always use `AppTheme.default`: the switch is a Debug-only
/// design tool, and a value left in a developer's defaults must never decide
/// what customers see.
@Observable
final class ThemeStore {
    static let storageKey = "appTheme"
    static let shared = ThemeStore()

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, honoursStoredChoice: Bool = ThemeStore.isSwitchAvailable) {
        self.defaults = defaults
        let stored = honoursStoredChoice ? defaults.string(forKey: Self.storageKey).flatMap(AppTheme.init(rawValue:)) : nil
        theme = stored ?? .default
    }

    /// Whether this build offers the Theme switch.
    static var isSwitchAvailable: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Tint

private struct ThemedTint: ViewModifier {
    func body(content: Content) -> some View {
        // Read here, inside a view's body, so switching themes re-tints
        // every system control below (sliders, toggles, alert buttons).
        content.tint(AppTheme.current.accent)
    }
}

extension View {
    /// Tints system controls with the current theme's accent.
    func themedTint() -> some View {
        modifier(ThemedTint())
    }
}
