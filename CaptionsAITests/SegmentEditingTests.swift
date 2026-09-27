@testable import CaptionsAI
import SwiftData
import XCTest

/// Editing a caption in the transcript sheet.
///
/// The defect: the sheet applied the new text and the new time range as two
/// separate calls, text first. Word timings are derived from the segment's
/// range, so they were spread across the range the caption was about to stop
/// having, and nothing recomputed them once the new range landed. Retime a
/// caption and its words stay behind — `activeWord(at:)` searches inside the
/// segment's own range and finds nothing, so word-by-word highlighting goes
/// dead for that caption, in the preview and in the export.
///
/// These assert through `activeWord(at:)` rather than the word array, because
/// highlighting is the thing the user sees.
@MainActor
final class SegmentEditingTests: XCTestCase {
    private func makeEditor() throws -> (EditorViewModel, CaptionSegment) {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)

        let segment = CaptionSegment(
            startTime: 0,
            endTime: 2,
            text: "one two",
            words: [
                WordTiming(word: "one", startTime: 0, endTime: 1),
                WordTiming(word: "two", startTime: 1, endTime: 2),
            ]
        )
        project.addSegment(segment)
        try context.save()

        return (EditorViewModel(project: project), segment)
    }

    // MARK: - The reported defect

    func testRetimingAndRewordingLeavesTheWordsInsideTheCaption() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "alpha beta gamma", start: 10, end: 13)

        XCTAssertEqual(segment.activeWord(at: 10.5)?.word, "alpha")
        XCTAssertEqual(segment.activeWord(at: 11.5)?.word, "beta")
        XCTAssertEqual(segment.activeWord(at: 12.5)?.word, "gamma")
    }

    func testRetimingDoesNotStrandTheWordsAtTheOldTime() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "alpha beta gamma", start: 10, end: 13)

        XCTAssertNil(
            segment.activeWord(at: 1.0),
            "a word is still highlighted at a time the caption no longer covers"
        )
        for word in segment.words {
            XCTAssertGreaterThanOrEqual(word.startTime, segment.startTime, word.word)
            XCTAssertLessThanOrEqual(word.endTime, segment.endTime, word.word)
        }
    }

    /// Every caption must be able to highlight something for the whole of its
    /// own range; a gap means a moment on screen with nothing lit.
    func testTheCaptionCanHighlightThroughoutItsRange() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "alpha beta gamma", start: 10, end: 13)

        for time in stride(from: 10.0, to: 13.0, by: 0.25) {
            XCTAssertNotNil(segment.activeWord(at: time), "nothing highlighted at \(time)")
        }
    }

    // MARK: - Retiming alone

    /// A nudge to the timing must carry the words along, and must not throw
    /// away what the recogniser measured by flattening them to an even spread.
    func testMovingACaptionCarriesItsUnevenWordTimingsWithIt() throws {
        let (editor, segment) = try makeEditor()
        segment.words = [
            WordTiming(word: "one", startTime: 0, endTime: 0.25),
            WordTiming(word: "two", startTime: 0.25, endTime: 2),
        ]

        editor.updateSegmentTiming(segment, start: 10, end: 12)

        XCTAssertEqual(segment.activeWord(at: 10.1)?.word, "one")
        XCTAssertEqual(segment.activeWord(at: 11.0)?.word, "two")
        XCTAssertEqual(segment.words.first?.duration ?? 0, 0.25, accuracy: 0.001,
                       "the short word was stretched to an even share")
    }

    func testStretchingACaptionScalesItsWordsProportionally() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegmentTiming(segment, start: 0, end: 4)

        XCTAssertEqual(segment.words.count, 2)
        XCTAssertEqual(segment.words[0].endTime, 2, accuracy: 0.001)
        XCTAssertEqual(segment.words[1].endTime, 4, accuracy: 0.001)
    }

    func testACaptionWithNoDurationStillPlacesItsWords() throws {
        let (editor, segment) = try makeEditor()
        segment.endTime = 0

        editor.updateSegmentTiming(segment, start: 5, end: 7)

        XCTAssertEqual(segment.activeWord(at: 5.5)?.word, "one")
        XCTAssertEqual(segment.activeWord(at: 6.5)?.word, "two")
    }

    // MARK: - Rewording alone

    func testRewordingSpreadsTheNewWordsOverTheExistingRange() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegmentText(segment, newText: "a b c d")

        XCTAssertEqual(segment.words.map(\.word), ["a", "b", "c", "d"])
        XCTAssertEqual(segment.activeWord(at: 0.1)?.word, "a")
        XCTAssertEqual(segment.activeWord(at: 1.9)?.word, "d")
    }

    /// Blank text is not saved: the caption keeps its words, and their
    /// timings, rather than becoming an invisible caption holding its slot.
    func testClearingTheTextKeepsTheCaptionAsItWas() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "", start: 0, end: 2)

        XCTAssertEqual(segment.text, "one two")
        XCTAssertEqual(segment.activeWord(at: 0.5)?.word, "one")
        XCTAssertEqual(segment.activeWord(at: 1.5)?.word, "two")
    }

    // MARK: - Persistence

    func testAnEditIsVisibleThroughTheViewModelsSegments() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "renamed", start: 3, end: 5)

        let seen = try XCTUnwrap(editor.segments.first { $0.id == segment.id })
        XCTAssertEqual(seen.text, "renamed")
        XCTAssertEqual(seen.startTime, 3)
        XCTAssertEqual(seen.activeWord(at: 4.0)?.word, "renamed")
    }
}
