import XCTest

/// Choose Video, end to end, on a real iPhone: the Photos picker, the copy
/// into the app, transcription, and the export screen it unlocks.
///
/// Device only. The simulator's picker cannot be driven reliably, so there
/// the test skips rather than pretends. On a device it picks one of the most
/// recent videos in the library, which should be a short clip with speech in it:
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
        // The phone lies face up on a desk while this runs. Each rotation
        // event made the picker re-lay itself out mid-query; pin it.
        XCUIDevice.shared.orientation = .portrait
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

        // Captions came out of it: at least one row, rather than merely no
        // empty state, which is also what a sheet that never loaded shows.
        app.button(containing: "Transcript").tap()
        let transcript = app.navigationBars["Transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: uiTimeout))
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: uiTimeout),
            "No captions — is the most recent video a clip with speech?"
        )
        XCTAssertFalse(app.staticTexts["No Captions"].exists)
        print("First caption row: \(firstRow.label)")

        // A fast swipe on the bar did not dismiss the sheet on the device;
        // drag it the whole way down instead.
        transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(transcript.waitForDisappearance(), "Transcript sheet did not dismiss")

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

    /// Taps a recent video in the system Photos picker.
    ///
    /// The picker runs out of process, but its grid is reachable through the
    /// app. Cells are labelled like "Video, 0:12, <date>"; the grid opens
    /// scrolled to the newest, so the first cell it exposes is a recent one. If no
    /// cell is found the element tree is attached, since the picker's layout
    /// is the part of this test most likely to change between iOS versions.
    @MainActor
    private func pickMostRecentVideo(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Work from snapshots, not queries. The picker's hierarchy lives in
        // another process and does not hold still: on the device a query
        // that had just matched a cell failed to match it again a moment
        // later, so anything that re-resolved it — count, index, frame, tap —
        // failed. A snapshot is one consistent copy of the tree; find the
        // cell in it and tap its centre by coordinate.
        let deadline = Date().addingTimeInterval(uiTimeout)
        var lastSnapshot: XCUIElementSnapshot?
        while Date() < deadline {
            if let snapshot = try? app.snapshot() {
                lastSnapshot = snapshot
                if let frame = Self.firstVideoFrame(in: snapshot) {
                    print("Photos picker: tapping a video cell at \(frame)")
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                        .tap()

                    // Single selection picks on tap; with an Add button, confirm.
                    let add = app.buttons["Add"]
                    if add.waitForExistence(timeout: 2) { add.tap() }
                    return
                }
            }
            Thread.sleep(forTimeInterval: Self.snapshotRetryInterval)
        }

        let tree = lastSnapshot.map { Self.outline($0) } ?? "no snapshot"
        print("Photos picker tree:\n\(tree)")
        let attachment = XCTAttachment(string: tree)
        attachment.name = "Picker element tree"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("No video cell in the Photos picker (tree printed above)", file: file, line: line)
    }

    /// How long to wait before taking another snapshot of a picker that is
    /// still appearing.
    static let snapshotRetryInterval: TimeInterval = 0.5

    /// The picker labels video cells "Video, <duration>, <date>".
    static func firstVideoFrame(in snapshot: XCUIElementSnapshot) -> CGRect? {
        let types: [XCUIElement.ElementType] = [.image, .cell, .button, .other]
        if types.contains(snapshot.elementType),
           snapshot.label.lowercased().hasPrefix("video"),
           !snapshot.frame.isEmpty {
            return snapshot.frame
        }
        for child in snapshot.children {
            if let frame = firstVideoFrame(in: child) { return frame }
        }
        return nil
    }

    /// Every labelled element, indented by depth: enough to see what the
    /// picker calls its cells without the full debug description.
    static func outline(_ snapshot: XCUIElementSnapshot, depth: Int = 0) -> String {
        var lines: [String] = []
        if !snapshot.label.isEmpty || !snapshot.identifier.isEmpty {
            let indent = String(repeating: "  ", count: depth)
            lines.append("\(indent)\(snapshot.elementType.rawValue) '\(snapshot.label)' id='\(snapshot.identifier)' \(snapshot.frame)")
        }
        for child in snapshot.children {
            let text = outline(child, depth: depth + 1)
            if !text.isEmpty { lines.append(text) }
        }
        return lines.joined(separator: "\n")
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
