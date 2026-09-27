import XCTest

/// Onboarding, the home screen, and the feedback menu with what hangs off it.
final class AppShellUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Onboarding

    @MainActor
    func testFirstLaunchShowsOnboardingAndGetStartedLeadsToAnEmptyLibrary() {
        let app = AppLauncher.launch(onboarded: false)

        XCTAssertTrue(app.staticTexts["No account needed"].waitForExistence(timeout: uiTimeout))
        app.buttons["Get Started"].tap()

        XCTAssertTrue(app.staticTexts[Copy.emptyLibraryTitle].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts[Copy.emptyLibraryMessage].exists)
        XCTAssertTrue(app.navigationBars["CaptionsAI"].exists)
    }

    @MainActor
    func testAnOnboardedUserGoesStraightToTheLibrary() {
        let app = AppLauncher.launch(onboarded: true)

        XCTAssertTrue(app.staticTexts[Copy.emptyLibraryTitle].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.buttons["Get Started"].exists)
    }

    // MARK: - Library

    @MainActor
    func testASeededProjectIsListedUnderRecentProjects() {
        let app = AppLauncher.launch(seed: .projectWithCaptions)

        XCTAssertTrue(app.staticTexts[Copy.recentProjects].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.button(containing: Copy.seededProjectName).exists)
        XCTAssertFalse(app.staticTexts[Copy.emptyLibraryTitle].exists)
    }

    @MainActor
    func testDeletingTheOnlyProjectAsksFirstThenEmptiesTheLibrary() {
        let app = AppLauncher.launch(seed: .projectWithCaptions)
        let card = app.button(containing: Copy.seededProjectName)
        XCTAssertTrue(card.waitForExistence(timeout: uiTimeout))

        card.press(forDuration: 1.0)
        let contextDelete = app.buttons["Delete"]
        XCTAssertTrue(contextDelete.waitForExistence(timeout: uiTimeout))
        contextDelete.tap()

        let prompt = "UI Test Project and its video will be removed from this device. This can't be undone."
        XCTAssertTrue(app.staticTexts[prompt].waitForExistence(timeout: uiTimeout))
        app.buttons["Delete"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts[Copy.emptyLibraryTitle].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.button(containing: Copy.seededProjectName).exists)
    }

    @MainActor
    func testCancellingTheDeleteKeepsTheProject() {
        let app = AppLauncher.launch(seed: .projectWithCaptions)
        let card = app.button(containing: Copy.seededProjectName)
        XCTAssertTrue(card.waitForExistence(timeout: uiTimeout))

        card.press(forDuration: 1.0)
        let contextDelete = app.buttons["Delete"]
        XCTAssertTrue(contextDelete.waitForExistence(timeout: uiTimeout))
        contextDelete.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: uiTimeout))
        cancel.tap()

        XCTAssertTrue(cancel.waitForDisappearance())
        XCTAssertTrue(app.button(containing: Copy.seededProjectName).exists)
        XCTAssertFalse(app.staticTexts[Copy.emptyLibraryTitle].exists)
    }

    // MARK: - Feedback menu

    @MainActor
    func testTheMenuOffersFeedbackProPrivacyAndTheVersion() {
        let app = AppLauncher.launch()
        app.openFeedbackMenu()

        XCTAssertTrue(app.buttons["Send feedback"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["Request a feature"].exists)
        XCTAssertTrue(app.buttons["CaptionsAI Pro"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)

        // "Version 1.0.0 (1)" today. Matched by shape so a version bump does
        // not fail it, while "Version unknown (unknown)" — the fallback when
        // the bundle keys are missing — still does.
        let version = app.elements(labelMatching: "label MATCHES %@", #"^Version [0-9]+(\.[0-9]+)* \([0-9]+\)$"#)
        XCTAssertEqual(version.count, 1)
    }

    @MainActor
    func testTheMenuNoLongerOffersToCopyTheEmailAddress() {
        let app = AppLauncher.launch()
        app.openFeedbackMenu()
        // Proves the menu is open, so the absence below means something.
        XCTAssertTrue(app.buttons["Send feedback"].waitForExistence(timeout: uiTimeout))

        XCTAssertEqual(app.elements(labelMatching: "label CONTAINS[c] %@", "copy").count, 0)
    }

    @MainActor
    func testSendFeedbackWithoutAMailAccountOffersOtherWaysToWrite() {
        // The simulator has no Apple Mail account, which is exactly the case
        // the contact sheet exists for.
        let app = AppLauncher.launch()
        app.openFeedbackMenu()
        let feedback = app.buttons["Send feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: uiTimeout))
        feedback.tap()

        XCTAssertTrue(app.navigationBars["Contact CaptionsAI"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["Copy address"].exists)
        XCTAssertTrue(app.buttons["Open default mail app"].exists)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Contact CaptionsAI"].waitForDisappearance())
    }

    // MARK: - Paywall

    @MainActor
    func testTheProRowOpensThePaywallAndCloseDismissesIt() {
        let app = AppLauncher.launch()
        app.openFeedbackMenu()
        let pro = app.buttons["CaptionsAI Pro"]
        XCTAssertTrue(pro.waitForExistence(timeout: uiTimeout))
        pro.tap()

        let restore = app.buttons["Restore Purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: uiTimeout))
        // A SwiftUI `Link`, whose element type varies; the label does not.
        XCTAssertTrue(app.elements(labelMatching: "label == %@", "Terms of Use").firstMatch.exists)

        app.buttons["Close"].tap()

        XCTAssertTrue(restore.waitForDisappearance())
        XCTAssertTrue(app.staticTexts[Copy.emptyLibraryTitle].exists)
    }
}
