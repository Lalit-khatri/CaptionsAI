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
    /// Mirrors `LanguagePreference.key`.
    static let languageArgument = "-transcriptionLanguage"

    /// Launches a fresh copy of the app.
    ///
    /// The language is always passed, English unless a test says otherwise.
    /// Left to the simulator's stored choice, a seeded empty project could
    /// open the editor in Kannada and start a 466 MB model download.
    static func launch(onboarded: Bool = true, seed: Seed? = nil, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            onboardingArgument, onboarded ? "YES" : "NO",
            languageArgument, language,
            inMemoryStoreArgument,
        ]
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

// MARK: - Sliders

@MainActor
extension XCUIElement {
    enum SliderEnd {
        case minimum, maximum
    }

    /// Half the width of UIKit's slider thumb. The thumb's centre runs from
    /// this far inside the left edge of the slider's frame to this far
    /// inside the right edge, not from edge to edge.
    private static let sliderThumbRadius: CGFloat = 14
    /// How far past the end of the track to drag. Inside the sheet's 20pt
    /// inset, so the drag never leaves the screen.
    private static let sliderOvershoot: CGFloat = 12

    /// Moves a slider to one end and waits for `reading` to appear, retrying
    /// the drag a couple of times.
    ///
    /// `adjust(toNormalizedSliderPosition:)` aims for the exact end and on
    /// the stepped text-size slider (4...48 in steps of 2) sometimes stopped
    /// short, so the tests that needed 4pt or 48pt failed intermittently in
    /// runs that changed nothing near the editor. This presses on the
    /// thumb's centre and drags past the end, which clamps to the end value.
    func drag(toEnd end: SliderEnd, until reading: XCUIElement, attempts: Int = 3) -> Bool {
        let radius = Self.sliderThumbRadius
        for _ in 0 ..< attempts {
            let width = frame.width
            let leftEdge = coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            let thumb = leftEdge.withOffset(CGVector(dx: radius + normalizedSliderPosition * (width - 2 * radius), dy: 0))
            let target = leftEdge.withOffset(
                CGVector(dx: end == .minimum ? -Self.sliderOvershoot : width + Self.sliderOvershoot, dy: 0)
            )
            thumb.press(forDuration: 0.1, thenDragTo: target)
            if reading.waitForExistence(timeout: 3) { return true }
        }
        return false
    }
}
