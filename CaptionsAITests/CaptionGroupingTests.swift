@testable import CaptionsAI
import XCTest

final class CaptionGroupingTests: XCTestCase {
    /// `count` words, one every `spacing` seconds, each lasting `length`.
    private func words(_ count: Int, spacing: Double = 0.3, length: Double = 0.25, from start: Double = 0) -> [WordTiming] {
        (0 ..< count).map { index in
            let wordStart = start + Double(index) * spacing
            return WordTiming(word: "w\(index)", startTime: wordStart, endTime: wordStart + length)
        }
    }

    func testNoWordsMakeNoCaptions() {
        XCTAssertEqual(CaptionGrouping.segments(from: []).count, 0)
    }

    func testAShortPhraseIsOneCaption() {
        let segments = CaptionGrouping.segments(from: words(3))
        XCTAssertEqual(segments.map(\.text), ["w0 w1 w2"])
        XCTAssertEqual(segments.first?.startTime, 0)
        XCTAssertEqual(segments.first?.endTime ?? 0, 0.85, accuracy: 1e-9)
    }

    func testACaptionEndsAfterEightWords() {
        let segments = CaptionGrouping.segments(from: words(10))
        XCTAssertEqual(segments.map { $0.words.count }, [8, 2])
        XCTAssertEqual(segments.map(\.sortOrder), [0, 1])
    }

    func testACaptionEndsOnceItSpansFourSeconds() {
        // One word a second: the fourth word's end is 3.9s after the first
        // word's start, the fifth crosses 4s.
        let segments = CaptionGrouping.segments(from: words(7, spacing: 1.0, length: 0.9))
        XCTAssertEqual(segments.map { $0.words.count }, [5, 2])
        XCTAssertEqual(segments[1].startTime, 5.0)
    }

    func testEachCaptionKeepsItsOwnWordTimings() {
        let input = words(10)
        let segments = CaptionGrouping.segments(from: input)
        XCTAssertEqual(segments.flatMap(\.words), input)
    }
}
