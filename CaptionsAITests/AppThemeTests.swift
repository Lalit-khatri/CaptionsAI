@testable import CaptionsAI
import XCTest

final class AppThemeTests: XCTestCase {
    // MARK: - The set

    func testWhiteShipsByDefault() {
        XCTAssertEqual(AppTheme.default, .snow)
        XCTAssertEqual(AppTheme.snow.displayName, "White")
    }

    func testWhiteHasBlackLabelsOnItsWhiteButtons() {
        XCTAssertEqual(AppTheme.snow.gradientHex.first, "#FFFFFF")
        XCTAssertEqual(AppTheme.snow.onPrimaryHex, "#000000")
    }

    func testTheSwitchOffersTheAgreedThemesInOrder() {
        XCTAssertEqual(AppTheme.allCases.map(\.displayName), ["Black", "Purple", "White", "Ocean", "Sunset", "Emerald"])
    }

    func testPurpleIsTheOriginalLook() {
        XCTAssertEqual(AppTheme.violet.gradientHex, ["#7C3AED", "#3B82F6"])
        XCTAssertEqual(AppTheme.violet.accentHex, "#7C3AED")
        XCTAssertEqual(AppTheme.violet.accentTextHex, "#A78BFA")
    }

    func testBlackUsesTheIconsYellowForSelection() {
        XCTAssertEqual(AppTheme.midnight.accentHex, "#FFD60A")
    }

    func testProgressOnBlackIsYellowNotCharcoal() {
        XCTAssertEqual(AppTheme.midnight.vividGradientHex, ["#FFD60A", "#FFB800"])
        XCTAssertEqual(AppTheme.violet.vividGradientHex, AppTheme.violet.gradientHex)
    }

    func testProgressStandsOutFromTheBlackBackground() {
        for theme in AppTheme.allCases {
            for stop in theme.vividGradientHex {
                XCTAssertGreaterThanOrEqual(Self.contrast(stop, "#000000"), 3.0, "\(theme.displayName): \(stop)")
            }
        }
    }

    // MARK: - Legibility, against WCAG contrast ratios

    func testButtonLabelsAreReadableOnEveryTheme() {
        // Button labels are 17pt semibold, which WCAG counts as large text:
        // 3:1 is the minimum.
        for theme in AppTheme.allCases {
            for stop in theme.gradientHex {
                XCTAssertGreaterThanOrEqual(
                    Self.contrast(theme.onPrimaryHex, stop), 3.0,
                    "\(theme.displayName): label on \(stop)"
                )
            }
        }
    }

    func testTextOnTheAccentIsReadable() {
        // Selected style tabs are 15pt, normal text: 4.5:1.
        for theme in AppTheme.allCases {
            XCTAssertGreaterThanOrEqual(Self.contrast(theme.onAccentHex, theme.accentHex), 4.5, theme.displayName)
        }
    }

    func testAccentTextIsReadableOnTheBlackBackground() {
        for theme in AppTheme.allCases {
            XCTAssertGreaterThanOrEqual(Self.contrast(theme.accentTextHex, "#000000"), 4.5, theme.displayName)
        }
    }

    func testSelectionMarksStandOutFromTheBlackBackground() {
        // Borders and checkmarks are non-text: 3:1.
        for theme in AppTheme.allCases {
            XCTAssertGreaterThanOrEqual(Self.contrast(theme.accentHex, "#000000"), 3.0, theme.displayName)
        }
    }

    // MARK: - Remembering the choice

    private let suite = "AppThemeTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAChosenThemeIsRemembered() {
        ThemeStore(defaults: defaults, honoursStoredChoice: true).theme = .ocean
        XCTAssertEqual(ThemeStore(defaults: defaults, honoursStoredChoice: true).theme, .ocean)
    }

    func testAReleaseBuildIgnoresAStoredChoice() {
        defaults.set(AppTheme.sunset.rawValue, forKey: ThemeStore.storageKey)
        XCTAssertEqual(ThemeStore(defaults: defaults, honoursStoredChoice: false).theme, .snow)
    }

    func testAnUnknownStoredValueFallsBackToWhite() {
        defaults.set("neon", forKey: ThemeStore.storageKey)
        XCTAssertEqual(ThemeStore(defaults: defaults, honoursStoredChoice: true).theme, .snow)
    }

    func testANewInstallStartsOnWhite() {
        XCTAssertEqual(ThemeStore(defaults: defaults, honoursStoredChoice: true).theme, .snow)
    }

    func testTheSwitchIsOnlyInDebugBuilds() {
        #if DEBUG
        XCTAssertTrue(ThemeStore.isSwitchAvailable)
        #else
        XCTAssertFalse(ThemeStore.isSwitchAvailable)
        #endif
    }

    // MARK: - Helpers

    private static func luminance(_ hex: String) -> Double {
        let value = Int(hex.dropFirst(), radix: 16)!
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { Double($0) / 255 }
        let linear = channels.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private static func contrast(_ a: String, _ b: String) -> Double {
        let (light, dark) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (light + 0.05) / (dark + 0.05)
    }
}
