@testable import CaptionsAI
import SwiftData
import XCTest

/// How often a segment's word timings are parsed.
///
/// The defect: `words` decoded its JSON on every single read, and the read in
/// the compositor sits *outside* the bitmap cache check — so an export parsed
/// the timings of the active segment once per frame, and the editor twice per
/// body evaluation at 20 Hz. The returned value was always correct, which is
/// why nothing caught it; the cost was invisible to any assertion about what
/// `words` gives back.
final class WordTimingCacheTests: XCTestCase {
    private func segment(words: Int) -> CaptionSegment {
        let timings = (0 ..< words).map {
            WordTiming(word: "word\($0)", startTime: Double($0), endTime: Double($0) + 1)
        }
        return CaptionSegment(startTime: 0, endTime: Double(words), text: "text", words: timings)
    }

    /// Parses attributable to `body`, whoever performs them.
    private func parses(during body: () -> Void) -> Int {
        let before = CaptionSegment.parseCount
        body()
        return CaptionSegment.parseCount - before
    }

    // MARK: - Reading repeatedly parses once

    func testReadingTheSameSegmentManyTimesParsesOnce() {
        let segment = segment(words: 50)

        let count = parses {
            for _ in 0 ..< 200 { _ = segment.words }
        }

        XCTAssertEqual(count, 1, "the JSON was parsed \(count) times for 200 reads")
    }

    /// `activeWord(at:)` is the per-frame caller, so it is the one that has to
    /// be cheap.
    func testScanningForTheActiveWordAcrossAClipParsesOnce() {
        let segment = segment(words: 30)

        let count = parses {
            for frame in 0 ..< 900 {
                _ = segment.activeWord(at: Double(frame) / 30.0)
            }
        }

        XCTAssertEqual(count, 1, "30 seconds of export parsed the timings \(count) times")
    }

    // MARK: - The cache still tells the truth

    func testTheWordsAreStillTheWordsThatWentIn() {
        let segment = segment(words: 3)

        XCTAssertEqual(segment.words.map(\.word), ["word0", "word1", "word2"])
        XCTAssertEqual(segment.words.map(\.word), ["word0", "word1", "word2"], "on a second read")
    }

    func testWritingNewWordsIsVisibleImmediately() {
        let segment = segment(words: 3)
        _ = segment.words

        segment.words = [WordTiming(word: "replaced", startTime: 0, endTime: 1)]

        XCTAssertEqual(segment.words.map(\.word), ["replaced"])
    }

    func testAssigningTheStoredDataDirectlyIsNotServedFromTheCache() throws {
        let segment = segment(words: 3)
        _ = segment.words

        let replacement = [WordTiming(word: "fromData", startTime: 0, endTime: 1)]
        segment.wordsData = try JSONEncoder().encode(replacement)

        XCTAssertEqual(segment.words.map(\.word), ["fromData"], "the cache outlived the data it came from")
    }

    func testASegmentWithNoTimingsHasNoWords() {
        let segment = CaptionSegment(startTime: 0, endTime: 1, text: "text")
        segment.wordsData = nil

        XCTAssertEqual(segment.words, [])
    }

    func testTwoSegmentsDoNotShareACache() {
        let first = segment(words: 2)
        let second = CaptionSegment(
            startTime: 0, endTime: 1, text: "other",
            words: [WordTiming(word: "different", startTime: 0, endTime: 1)]
        )

        XCTAssertEqual(first.words.map(\.word), ["word0", "word1"])
        XCTAssertEqual(second.words.map(\.word), ["different"])
    }

    // MARK: - It survives a round trip through the store

    func testWordsLoadedFromTheStoreAreCorrect() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let segment = segment(words: 4)
        context.insert(segment)
        try context.save()

        let fetched = try ModelContext(container).fetch(FetchDescriptor<CaptionSegment>())
        let loaded = try XCTUnwrap(fetched.first)

        XCTAssertEqual(loaded.words.map(\.word), ["word0", "word1", "word2", "word3"])
    }
}
