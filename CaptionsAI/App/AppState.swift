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

    var dailyExportCount: Int {
        get {
            resetExportCountIfNewDay()
            return UserDefaults.standard.integer(forKey: "dailyExportCount")
        }
        set { UserDefaults.standard.set(newValue, forKey: "dailyExportCount") }
    }

    var isPro: Bool = false

    // MARK: - Constants

    static let freeExportLimit = 2

    // MARK: - Methods

    func incrementExportCount() {
        dailyExportCount += 1
    }

    func canExport() -> Bool {
        isPro || dailyExportCount < Self.freeExportLimit
    }

    private func resetExportCountIfNewDay() {
        let lastResetDate = UserDefaults.standard.object(forKey: "lastExportResetDate") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(lastResetDate) {
            UserDefaults.standard.set(0, forKey: "dailyExportCount")
            UserDefaults.standard.set(Date(), forKey: "lastExportResetDate")
        }
    }
}

// MARK: - Navigation Destinations

enum AppScreen: Hashable {
    case onboarding
    case importVideo
    case editor(Project)
    case preview(Project)
    case export(Project)
    case paywall

    /// Hashable conformance for Project (uses id)
    func hash(into hasher: inout Hasher) {
        switch self {
        case .onboarding: hasher.combine("onboarding")
        case .importVideo: hasher.combine("import")
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
        case let (.editor(a), .editor(b)): return a.id == b.id
        case let (.preview(a), .preview(b)): return a.id == b.id
        case let (.export(a), .export(b)): return a.id == b.id
        case (.paywall, .paywall): return true
        default: return false
        }
    }
}
