import XCTest

/// Choosing the language new videos are transcribed in.
///
/// None of these accept the model download: that would pull 466 MB from
/// Hugging Face on every run. The paths that matter without it are that the
/// app asks before downloading, and that saying no changes nothing.
final class LanguageUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func languageButton(in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["languageButton"]
        XCTAssertTrue(button.waitForExistence(timeout: uiTimeout), "No language row on the home screen")
        return button
    }

    @MainActor
    func testTheHomeScreenSaysVideosAreTranscribedInEnglishByDefault() {
        let app = AppLauncher.launch()
        let button = languageButton(in: app)
        XCTAssertTrue(button.label.contains("English"), button.label)
        XCTAssertFalse(button.label.contains("Model not downloaded"), "English needs no model: \(button.label)")
    }

    @MainActor
    func testPickingKannadaAsksBeforeDownloadingAndCancelKeepsEnglish() {
        let app = AppLauncher.launch()
        languageButton(in: app).tap()

        let search = app.searchFields["Search languages"]
        XCTAssertTrue(search.waitForExistence(timeout: uiTimeout))
        search.tap()
        search.typeText("kan")

        let kannada = app.buttons["language-kn"]
        XCTAssertTrue(kannada.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.buttons["language-hi"].exists, "search did not narrow the list")
        kannada.tap()

        let alert = app.alerts["Download speech model?"]
        XCTAssertTrue(alert.waitForExistence(timeout: uiTimeout), "picked Kannada without asking to download")
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "466 MB")).firstMatch
        XCTAssertTrue(message.exists, "the prompt does not say how big the download is")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForDisappearance())

        // While the search field is active the toolbar is hidden behind it;
        // its "Close" button gives the toolbar back.
        app.buttons["Close"].tap()
        let cancel = app.buttons["languagePickerCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: uiTimeout))
        cancel.tap()
        let button = languageButton(in: app)
        XCTAssertTrue(button.label.contains("English"), "declining the download still changed the language: \(button.label)")
    }

    @MainActor
    func testAWhisperLanguageWithoutItsModelSaysSoAndEnglishSwitchesBack() {
        let app = AppLauncher.launch(language: "hi")
        let button = languageButton(in: app)
        XCTAssertTrue(button.label.contains("Hindi"), button.label)
        XCTAssertTrue(button.label.contains("Model not downloaded"), button.label)

        button.tap()
        let english = app.buttons["language-en"]
        XCTAssertTrue(english.waitForExistence(timeout: uiTimeout))
        english.tap()

        XCTAssertTrue(english.waitForDisappearance(), "the picker stayed open after choosing English")
        XCTAssertTrue(languageButton(in: app).label.contains("English"))
    }
}
