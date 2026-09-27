import XCTest

// MARK: - Launching

/// Starts the app the way every UI test needs it: never against the real
/// library, and with onboarding either done or not, as the test says.
///
/// The argument strings mirror `UITestLaunch` in the app. They are repeated
/// here rather than shared because a UI test bundle cannot import the app;
/// if they drift apart, every seeded test fails at its first lookup.
@MainActor
enum AppLauncher {
    /// Seeds `UITestLaunch.Seed` understands.
    enum Seed: String {
        case projectWithCaptions
        case emptyProject
    }

    static let inMemoryStoreArgument = "-uiTestInMemoryStore"
    static let seedArgument = "-uiTestSeed"
    static let onboardingArgument = "-hasCompletedOnboarding"

    /// Launches a fresh copy of the app.
    static func launch(onboarded: Bool = true, seed: Seed? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [onboardingArgument, onboarded ? "YES" : "NO", inMemoryStoreArgument]
        if let seed {
            arguments += [seedArgument, seed.rawValue]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

// MARK: - What the app shows

/// Copy the tests look for, as literals: the point is to notice when what
/// the user sees changes.
enum Copy {
    static let seededProjectName = "UI Test Project"
    static let firstCaption = "Hello from the UI tests"
    static let secondCaption = "A second caption"
    static let newCaption = "New caption"

    static let emptyLibraryTitle = "No projects yet"
    static let emptyLibraryMessage = "Videos you caption will show up here."
    static let recentProjects = "Recent Projects"

    static let menuButton = "Feedback and app info"
}

// MARK: - Waiting

/// Long enough for a cold launch on a busy simulator. Every wait is on a
/// condition, so a fast run never sleeps this long.
let uiTimeout: TimeInterval = 15

/// For asserting something is absent right after an action that should
/// have removed it: animations need a moment to finish.
let disappearanceTimeout: TimeInterval = 5

@MainActor
extension XCUIElement {
    /// Waits for the element to leave the hierarchy.
    func waitForDisappearance(timeout: TimeInterval = disappearanceTimeout) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

@MainActor
extension XCUIApplication {
    /// The first button whose label contains `text`.
    ///
    /// For buttons whose label SwiftUI builds from an icon and a caption —
    /// the editor's action bar, the project cards — where the exact spoken
    /// form of the icon is not something a test should pin.
    func button(containing text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Any element, of any type, whose label matches `format`.
    func elements(labelMatching format: String, _ arguments: CVarArg...) -> XCUIElementQuery {
        descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: arguments))
    }

    /// Opens the feedback menu in the top-right corner.
    func openFeedbackMenu(file: StaticString = #filePath, line: UInt = #line) {
        let menu = buttons[Copy.menuButton]
        XCTAssertTrue(menu.waitForExistence(timeout: uiTimeout), "No feedback menu button", file: file, line: line)
        menu.tap()
    }
}
