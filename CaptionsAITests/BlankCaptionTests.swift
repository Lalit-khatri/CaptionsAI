@testable import CaptionsAI
import SwiftData
import XCTest

/// A caption cannot be saved blank.
///
/// It used to be: the caption drew nothing but still held its time range,
/// invisible in the preview, with no obvious way to find it again.
@MainActor
final class BlankCaptionTests: XCTestCase {
    private func makeEditor() throws -> (EditorViewModel, CaptionSegment) {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: 20)
        context.insert(project)
        let segment = CaptionSegment(startTime: 0, endTime: 2, text: "keep me")
        project.addSegment(segment)
        try context.save()
        return (EditorViewModel(project: project, speechRecognizer: FakeTranscriber(), audioSession: FakeAudioSession()), segment)
    }

    // MARK: - captionText(from:)

    func testOrdinaryTextIsKept() {
        XCTAssertEqual(EditorViewModel.captionText(from: "hello world"), "hello world")
    }

    func testSurroundingWhitespaceAndNewlinesAreTrimmed() {
        XCTAssertEqual(EditorViewModel.captionText(from: "  hello\n world \n"), "hello\n world")
    }

    func testEmptyTextIsRejected() {
        XCTAssertNil(EditorViewModel.captionText(from: ""))
    }

    func testWhitespaceOnlyTextIsRejected() {
        XCTAssertNil(EditorViewModel.captionText(from: " \t\n  "))
    }

    // MARK: - Through the editor

    func testSavingBlankTextKeepsTheOldTextButAppliesTheNewTiming() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "   ", start: 5, end: 7)

        XCTAssertEqual(segment.text, "keep me")
        XCTAssertEqual([segment.startTime, segment.endTime], [5, 7])
    }

    func testRewordingToBlankIsIgnored() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegmentText(segment, newText: "\n")

        XCTAssertEqual(segment.text, "keep me")
    }

    func testSavedTextIsStoredTrimmed() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegmentText(segment, newText: "  new words \n")

        XCTAssertEqual(segment.text, "new words")
    }

    /// Adding a caption with blank text still produces a visible caption.
    func testAddingWithBlankTextUsesThePlaceholder() throws {
        let (editor, _) = try makeEditor()

        let added = editor.addSegment(at: 10, text: " ")

        XCTAssertEqual(added.text, "New caption")
    }

    // MARK: - The Save button

    func testSaveIsOfferedForText() {
        XCTAssertTrue(SegmentEditorSheet.canSave(text: "hi"))
    }

    func testSaveIsNotOfferedForBlankText() {
        XCTAssertFalse(SegmentEditorSheet.canSave(text: ""))
        XCTAssertFalse(SegmentEditorSheet.canSave(text: " \n "))
    }
}
