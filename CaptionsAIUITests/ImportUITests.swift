import XCTest

/// Choose Video, end to end, on a real iPhone: the Photos picker, the copy
/// into the app, transcription, and the export screen it unlocks.
///
/// Device only. The simulator's picker cannot be driven reliably, so there
/// the test skips rather than pretends. On a device it picks the most recent
/// video in the library, which should be a short clip with speech in it:
/// with no speech there are no captions, and the test says so.
///
/// It stops at the export settings. Exporting would save a video into the
/// device's photo library, which a test has no business doing.
final class ImportUITests: XCTestCase {
    /// Speech recognition of a short clip on-device. Generous, because the
    /// first run on a device may download the recognizer's assets.
    static let transcriptionTimeout: TimeInterval = 180

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testChoosingAVideoTranscribesItAndOpensTheExportSettings() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Choose Video needs a real photo library; run on a device.")
        #else
        let app = AppLauncher.launch()
        let choose = app.button(containing: "Choose Video")
        XCTAssertTrue(choose.waitForExistence(timeout: uiTimeout))
        choose.tap()

        pickMostRecentVideo(in: app)

        // The import lands in the editor, which transcribes straight away.
        XCTAssertTrue(app.navigationBars["Edit"].waitForExistence(timeout: uiTimeout), "Editor did not open after picking")
        allowSpeechRecognitionIfAsked()
        let analyzing = app.staticTexts["Analyzing Speech..."]
        if analyzing.waitForExistence(timeout: disappearanceTimeout) {
            XCTAssertTrue(
                analyzing.waitForDisappearance(timeout: Self.transcriptionTimeout),
                "Transcription did not finish in \(Int(Self.transcriptionTimeout))s"
            )
        }
        XCTAssertFalse(app.alerts["Error"].exists, "Editor reported: \(app.alerts["Error"].staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(app.staticTexts["Video unavailable"].exists)

        // Captions came out of it.
        app.button(containing: "Transcript").tap()
        XCTAssertTrue(app.navigationBars["Transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(
            app.staticTexts["No Captions"].waitForExistence(timeout: disappearanceTimeout),
            "No captions — is the most recent video a clip with speech?"
        )
        app.navigationBars["Transcript"].swipeDown(velocity: .fast)
        XCTAssertTrue(app.navigationBars["Transcript"].waitForDisappearance())

        // With a real video, Export is live and leads to the settings.
        let export = app.button(containing: "Export")
        XCTAssertTrue(export.isEnabled)
        export.tap()
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Format"].exists)
        XCTAssertTrue(app.staticTexts["Resolution"].exists)
        XCTAssertTrue(app.staticTexts["Summary"].exists)
        XCTAssertTrue(app.button(containing: "Export Video").isEnabled)

        // The two sections taken off this screen stay off it.
        XCTAssertFalse(app.staticTexts["Include Audio"].exists)
        XCTAssertEqual(app.elements(labelMatching: "label == %@", "Quality").count, 0)
        #endif
    }

    // MARK: - Steps

    /// Taps the newest video in the system Photos picker.
    ///
    /// The picker runs out of process, but its grid is reachable through the
    /// app. Cells are labelled like "Video, 0:12, <date>"; the grid opens
    /// scrolled to the newest, which is the last cell in element order. If no
    /// cell is found the element tree is attached, since the picker's layout
    /// is the part of this test most likely to change between iOS versions.
    @MainActor
    private func pickMostRecentVideo(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let videos = app.elements(labelMatching: "label BEGINSWITH[c] %@", "Video")
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d OR elementType == %d",
                                  XCUIElement.ElementType.image.rawValue,
                                  XCUIElement.ElementType.cell.rawValue,
                                  XCUIElement.ElementType.button.rawValue))
        guard videos.firstMatch.waitForExistence(timeout: uiTimeout) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Picker element tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("No video in the Photos picker (element tree attached)", file: file, line: line)
            return
        }

        let hittable = videos.allElementsBoundByIndex.filter(\.isHittable)
        (hittable.last ?? videos.firstMatch).tap()

        // Single selection picks on tap; with an Add button, confirm.
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 2) { add.tap() }
    }

    /// Accepts the one-time speech permission prompt, which belongs to
    /// SpringBoard rather than the app. Already granted: nothing to do.
    @MainActor
    private func allowSpeechRecognitionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: disappearanceTimeout) {
            allow.tap()
        }
    }
}
