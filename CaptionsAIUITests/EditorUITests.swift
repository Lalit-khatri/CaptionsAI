import XCTest

/// The editor, reached from a seeded project whose video file is missing.
///
/// A missing video is deliberate: the editor then neither plays nor
/// transcribes, so every test starts from the same captions. It also means
/// Export stays disabled, so the export screen is out of reach here.
final class EditorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Opening

    @MainActor
    func testAProjectWhoseVideoIsGoneOpensWithVideoUnavailableAndNoExport() {
        let app = openEditor()

        XCTAssertTrue(app.staticTexts["Video unavailable"].waitForExistence(timeout: uiTimeout))
        let export = app.button(containing: "Export")
        XCTAssertTrue(export.exists)
        XCTAssertFalse(export.isEnabled)
    }

    // MARK: - Transcript

    @MainActor
    func testTheTranscriptListsTheCaptionsInTimeOrder() {
        let app = openEditor()
        openTranscript(app)

        let first = app.staticTexts[Copy.firstCaption]
        let second = app.staticTexts[Copy.secondCaption]
        XCTAssertTrue(first.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
    }

    @MainActor
    func testSavingAnEditedCaptionShowsTheNewTextInTheTranscript() {
        let app = openEditor()
        openTranscript(app)
        openCaption(Copy.firstCaption, in: app)

        let editor = app.textViews.firstMatch
        replaceText(in: editor, with: "Edited by a UI test")
        saveButton(app).tap()

        XCTAssertTrue(app.staticTexts["Edited by a UI test"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.staticTexts[Copy.firstCaption].exists)
        XCTAssertTrue(app.staticTexts[Copy.secondCaption].exists)
    }

    @MainActor
    func testBlankTextDisablesSaveAndCancelKeepsTheCaption() {
        let app = openEditor()
        openTranscript(app)
        openCaption(Copy.firstCaption, in: app)
        let save = saveButton(app)
        XCTAssertTrue(save.isEnabled)

        replaceText(in: app.textViews.firstMatch, with: "   ")
        XCTAssertFalse(save.isEnabled)

        app.navigationBars["Edit Caption"].buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Edit Caption"].waitForDisappearance())
        XCTAssertTrue(app.staticTexts[Copy.firstCaption].exists)
    }

    @MainActor
    func testAddCaptionOpensItForEditingAndKeepsItAfterCancel() {
        let app = openEditor()
        openTranscript(app)

        app.navigationBars["Transcript"].buttons["Add Caption"].tap()

        XCTAssertTrue(app.navigationBars["Edit Caption"].waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(app.textViews.firstMatch.value as? String, Copy.newCaption)

        app.navigationBars["Edit Caption"].buttons["Cancel"].tap()

        // Added before it was opened, so cancelling the edit keeps the row.
        XCTAssertTrue(app.staticTexts[Copy.newCaption].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts[Copy.firstCaption].exists)
        XCTAssertTrue(app.staticTexts[Copy.secondCaption].exists)
    }

    @MainActor
    func testSwipingACaptionAwayDeletesOnlyThatCaption() {
        let app = openEditor()
        openTranscript(app)
        let second = app.staticTexts[Copy.secondCaption]
        XCTAssertTrue(second.waitForExistence(timeout: uiTimeout))

        second.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: uiTimeout))
        delete.tap()

        XCTAssertTrue(second.waitForDisappearance())
        XCTAssertTrue(app.staticTexts[Copy.firstCaption].exists)
    }

    @MainActor
    func testAProjectWithNoCaptionsOffersToAddOne() {
        let app = openEditor(seed: .emptyProject)
        openTranscript(app)

        XCTAssertTrue(app.staticTexts["No Captions"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Add a caption at the current point in the video."].exists)
        // One in the toolbar, one in the empty state.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Add Caption")).count, 2)
    }

    // MARK: - Style

    @MainActor
    func testTheTextSizeSliderGoesDownToFourPointsAndUpToFortyEight() {
        let app = openEditor()
        app.button(containing: "Style").tap()

        XCTAssertTrue(app.staticTexts["Caption Style"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Text Size"].exists)
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.exists)

        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.staticTexts["4pt"].waitForExistence(timeout: uiTimeout))

        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(app.staticTexts["48pt"].waitForExistence(timeout: uiTimeout))
    }

    // MARK: - Steps

    /// Launches with `seed` and opens its project in the editor.
    @MainActor
    private func openEditor(
        seed: AppLauncher.Seed = .projectWithCaptions,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = AppLauncher.launch(seed: seed)
        let card = app.button(containing: Copy.seededProjectName)
        XCTAssertTrue(card.waitForExistence(timeout: uiTimeout), "No project card", file: file, line: line)
        card.tap()
        XCTAssertTrue(app.navigationBars["Edit"].waitForExistence(timeout: uiTimeout), "Editor did not open", file: file, line: line)

        // A project with no captions asks to transcribe on open, and with no
        // video that ends in an error alert. Not what these tests are about,
        // but it has to be out of the way before anything else is tapped.
        if seed == .emptyProject {
            let alert = app.alerts["Error"]
            if alert.waitForExistence(timeout: disappearanceTimeout) {
                alert.buttons["OK"].tap()
                XCTAssertTrue(alert.waitForDisappearance(), file: file, line: line)
            }
        }
        return app
    }

    @MainActor
    private func openTranscript(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.button(containing: "Transcript").tap()
        XCTAssertTrue(app.navigationBars["Transcript"].waitForExistence(timeout: uiTimeout), "Transcript did not open", file: file, line: line)
    }

    @MainActor
    private func openCaption(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.staticTexts[text]
        XCTAssertTrue(row.waitForExistence(timeout: uiTimeout), "No row for \(text)", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Caption"].waitForExistence(timeout: uiTimeout), "Caption editor did not open", file: file, line: line)
    }

    @MainActor
    private func saveButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars["Edit Caption"].buttons["Save"]
    }

    /// Clears the text view and types `text`.
    ///
    /// Tapping low in the view puts the caret after the last character, and
    /// one delete per character then empties it, whatever it held.
    @MainActor
    private func replaceText(in textView: XCUIElement, with text: String) {
        textView.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        let existing = (textView.value as? String) ?? ""
        textView.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        textView.typeText(text)
    }
}
