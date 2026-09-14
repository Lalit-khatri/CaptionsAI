import SwiftUI

// MARK: - App State

/// Global application state managing navigation and user preferences.
@Observable
final class AppState {
    // MARK: - Navigation

    var navigationPath = NavigationPath()

    // MARK: - User Preferences

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Constants

    /// Exports a free user gets per day. Pro is unlimited.
    ///
    /// `ExportViewModel` owns the counting and the daily reset. A second copy
    /// of that logic used to live here — its own `dailyExportCount`,
    /// `canExport()` and `incrementExportCount()`, over the same UserDefaults
    /// key, plus an `isPro` mirror nothing ever assigned, so it answered
    /// "not pro" forever. Nothing called any of it. It is gone rather than
    /// reconciled: one owner of a rule is the only way it stays true.
    static let freeExportLimit = 5
}

// MARK: - Navigation Destinations

enum AppScreen: Hashable {
    case onboarding
    case importVideo
    case allProjects
    case editor(Project)
    case preview(Project)
    case export(Project)
    case paywall

    /// Hashable conformance for Project (uses id)
    func hash(into hasher: inout Hasher) {
        switch self {
        case .onboarding: hasher.combine("onboarding")
        case .importVideo: hasher.combine("import")
        case .allProjects: hasher.combine("allProjects")
        case let .editor(p): hasher.combine("editor"); hasher.combine(p.id)
        case let .preview(p): hasher.combine("preview"); hasher.combine(p.id)
        case let .export(p): hasher.combine("export"); hasher.combine(p.id)
        case .paywall: hasher.combine("paywall")
        }
    }

    static func == (lhs: AppScreen, rhs: AppScreen) -> Bool {
        switch (lhs, rhs) {
        case (.onboarding, .onboarding): return true
        case (.importVideo, .importVideo): return true
        case (.allProjects, .allProjects): return true
        case let (.editor(a), .editor(b)): return a.id == b.id
        case let (.preview(a), .preview(b)): return a.id == b.id
        case let (.export(a), .export(b)): return a.id == b.id
        case (.paywall, .paywall): return true
        default: return false
        }
    }
}
