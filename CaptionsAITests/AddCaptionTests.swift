@testable import CaptionsAI
import SwiftData
import UIKit
import XCTest

/// Adding a caption by hand from the transcript sheet.
///
/// The only way to get captions was transcription. Delete them all, or
/// import a clip with no speech, and the editor had no way to add one.
@MainActor
final class AddCaptionTests: XCTestCase {
    private func makeEditor(videoDuration: Double, captions: [(Double, Double, String)] = []) throws -> EditorViewModel {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: videoDuration)
        context.insert(project)
        for (index, caption) in captions.enumerated() {
            project.addSegment(CaptionSegment(startTime: caption.0, endTime: caption.1, text: caption.2, sortOrder: index))
        }
        try context.save()
        return EditorViewModel(project: project, speechRecognizer: FakeTranscriber(), audioSession: FakeAudioSession())
    }

    private func range(at time: Double, in duration: Double) -> [Double] {
        let range = EditorViewModel.newCaptionRange(at: time, videoDuration: duration)
        return [range.start, range.end]
    }

    // MARK: - Where the caption goes

    func testACaptionAddedMidVideoLastsTwoSecondsFromThePlayhead() {
        XCTAssertEqual(range(at: 3, in: 10), [3, 5])
    }

    /// Clipping at the end made a zero-length caption nobody could see.
    func testACaptionAddedAtTheLastSecondIsPulledBackToFit() {
        XCTAssertEqual(range(at: 10, in: 10), [8, 10])
    }

    func testACaptionAddedNearTheEndIsPulledBackToFit() {
        XCTAssertEqual(range(at: 9.5, in: 10), [8, 10])
    }

    func testAVideoShorterThanACaptionGetsOneCaptionOverAllOfIt() {
        XCTAssertEqual(range(at: 0.5, in: 1.5), [0, 1.5])
    }

    func testAnUnknownDurationClipsNothing() {
        XCTAssertEqual(range(at: 42, in: 0), [42, 44])
    }

    func testANegativePlayheadStartsAtZero() {
        XCTAssertEqual(range(at: -1, in: 10), [0, 2])
    }

    // MARK: - What gets added

    func testAnEmptyProjectGetsTheNewCaption() throws {
        let editor = try makeEditor(videoDuration: 10)

        let added = editor.addSegment(at: 3)

        XCTAssertEqual(editor.segments.map(\.text), ["New caption"])
        XCTAssertEqual(editor.project.segments.map(\.id), [added.id])
        XCTAssertEqual([added.startTime, added.endTime], [3, 5])
    }

    /// Word-by-word styles need word timings, or nothing ever highlights.
    func testTheNewCaptionHighlightsItsWordsInTurn() throws {
        let editor = try makeEditor(videoDuration: 10)

        let added = editor.addSegment(at: 3)

        XCTAssertEqual(added.activeWord(at: 3.5)?.word, "New")
        XCTAssertEqual(added.activeWord(at: 4.5)?.word, "caption")
    }

    func testCustomTextIsUsedAndTimed() throws {
        let editor = try makeEditor(videoDuration: 10)

        let added = editor.addSegment(at: 0, text: "one two three four")

        XCTAssertEqual(added.text, "one two three four")
        XCTAssertEqual(added.words.map(\.word), ["one", "two", "three", "four"])
        XCTAssertEqual(added.words.map(\.startTime), [0, 0.5, 1, 1.5])
    }

    func testTheNewCaptionIsOrderedByTimeAmongTheOthers() throws {
        let editor = try makeEditor(videoDuration: 10, captions: [(0, 1, "first"), (6, 7, "last")])

        editor.addSegment(at: 3)

        XCTAssertEqual(editor.segments.map(\.text), ["first", "New caption", "last"])
    }

    func testAddingMarksTheProjectModified() throws {
        let editor = try makeEditor(videoDuration: 10)
        let before = Date(timeIntervalSince1970: 0)
        editor.project.modifiedAt = before

        editor.addSegment(at: 3)

        XCTAssertGreaterThan(editor.project.modifiedAt, before)
    }

    // MARK: - The sheet

    func testTheSheetsSymbolsResolve() {
        XCTAssertNotNil(UIImage(systemName: TranscriptSheetView.addSymbol))
        XCTAssertNotNil(UIImage(systemName: TranscriptSheetView.emptySymbol))
    }
}
