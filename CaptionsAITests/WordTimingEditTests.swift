@testable import CaptionsAI
import SwiftData
import XCTest

/// Whether editing a caption's wording keeps the recogniser's word timings.
///
/// Fixing one misheard word used to re-spread every word evenly across the
/// caption, throwing away where each was actually spoken. The highlight then
/// ran ahead of or behind the voice for the whole caption.
@MainActor
final class WordTimingEditTests: XCTestCase {
    /// Uneven on purpose: "hello" is short, "world" is long. An even spread
    /// would put the boundary at 1.0.
    private let measured = [
        WordTiming(word: "hello", startTime: 0, endTime: 0.4),
        WordTiming(word: "wrld", startTime: 0.4, endTime: 2),
    ]

    private func boundaries(_ words: [WordTiming]) -> [[Double]] {
        words.map { [$0.startTime, $0.endTime] }
    }

    private func makeEditor() throws -> (EditorViewModel, CaptionSegment) {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        let segment = CaptionSegment(startTime: 0, endTime: 2, text: "hello wrld", words: measured)
        project.addSegment(segment)
        try context.save()
        return (EditorViewModel(project: project, speechRecognizer: FakeTranscriber(), audioSession: FakeAudioSession()), segment)
    }

    // MARK: - wordTimings(for:keeping:from:to:)

    func testTheSameNumberOfWordsKeepsEveryTiming() {
        let words = EditorViewModel.wordTimings(for: "hello world", keeping: measured, from: 0, to: 2)

        XCTAssertEqual(words.map(\.word), ["hello", "world"])
        XCTAssertEqual(boundaries(words), [[0, 0.4], [0.4, 2]])
    }

    func testADifferentNumberOfWordsIsSpreadEvenly() {
        let words = EditorViewModel.wordTimings(for: "hello there world", keeping: measured, from: 0, to: 3)

        XCTAssertEqual(words.map(\.word), ["hello", "there", "world"])
        XCTAssertEqual(boundaries(words), [[0, 1], [1, 2], [2, 3]])
    }

    func testFewerWordsAreSpreadEvenly() {
        let words = EditorViewModel.wordTimings(for: "hello", keeping: measured, from: 0, to: 2)

        XCTAssertEqual(boundaries(words), [[0, 2]])
    }

    func testWithNoExistingTimingsTheWordsAreSpreadEvenly() {
        let words = EditorViewModel.wordTimings(for: "a b", keeping: [], from: 0, to: 2)

        XCTAssertEqual(boundaries(words), [[0, 1], [1, 2]])
    }

    /// A line break typed in the editor separates words like a space does.
    func testALineBreakSeparatesWords() {
        let words = EditorViewModel.wordTimings(for: "hello\nworld", keeping: measured, from: 0, to: 2)

        XCTAssertEqual(words.map(\.word), ["hello", "world"])
        XCTAssertEqual(boundaries(words), [[0, 0.4], [0.4, 2]])
    }

    func testRunsOfSpacesAndTabsDoNotMakeEmptyWords() {
        let words = EditorViewModel.wordTimings(for: "  hello \t  world  ", keeping: measured, from: 0, to: 2)

        XCTAssertEqual(words.map(\.word), ["hello", "world"])
    }

    func testNoWordsGivesNoTimings() {
        XCTAssertEqual(EditorViewModel.wordTimings(for: " \n ", keeping: measured, from: 0, to: 2).count, 0)
    }

    // MARK: - Through the editor

    func testFixingATypoKeepsWhereEachWordWasSpoken() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegmentText(segment, newText: "hello world")

        XCTAssertEqual(segment.text, "hello world")
        XCTAssertEqual(segment.activeWord(at: 0.3)?.word, "hello")
        XCTAssertEqual(segment.activeWord(at: 0.5)?.word, "world")
    }

    /// The sheet saves text and timing together. Moving the caption and
    /// fixing a typo at once keeps the measured proportions at the new time.
    func testFixingATypoWhileMovingKeepsTheProportions() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "hello world", start: 10, end: 14)

        XCTAssertEqual(segment.words.map(\.word), ["hello", "world"])
        XCTAssertEqual(segment.words[0].startTime, 10, accuracy: 0.001)
        XCTAssertEqual(segment.words[0].endTime, 10.8, accuracy: 0.001)
        XCTAssertEqual(segment.words[1].endTime, 14, accuracy: 0.001)
    }

    func testAddingAWordWhileMovingSpreadsOverTheNewRange() throws {
        let (editor, segment) = try makeEditor()

        editor.updateSegment(segment, text: "hello big world", start: 10, end: 13)

        XCTAssertEqual(boundaries(segment.words), [[10, 11], [11, 12], [12, 13]])
    }
}
