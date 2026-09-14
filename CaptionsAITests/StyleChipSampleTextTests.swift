@testable import CaptionsAI
import XCTest

/// The string the style chips draw.
///
/// Two words of "Hello World" told a user nothing about a caption style: no
/// wrap, no rhythm, and with word-by-word highlighting, half the sample lit up.
/// The sample is now a short sentence, and it is topped up across segments
/// rather than taken from the first one alone — a transcript's first segment is
/// frequently one or two words.
final class StyleChipSampleTextTests: XCTestCase {
    // MARK: - Where the sample comes from

    func testTheSampleIsTheFirstSixWordsOfTheTranscript() {
        XCTAssertEqual(
            EditorView.previewText(segmentTexts: ["one two three four five six seven eight"]),
            "one two three four five six"
        )
    }

    func testAShorterSegmentIsUsedWhole() {
        XCTAssertEqual(EditorView.previewText(segmentTexts: ["two words"]), "two words")
    }

    /// The defect this rule exists for: a transcript's first segment is often
    /// a single word, and the chip then had one word to show.
    func testAShortFirstSegmentIsToppedUpFromTheNext() {
        XCTAssertEqual(
            EditorView.previewText(segmentTexts: ["So", "here is the whole idea really"]),
            "So here is the whole idea"
        )
    }

    func testSegmentsAreJoinedInOrder() {
        XCTAssertEqual(
            EditorView.previewText(segmentTexts: ["alpha", "bravo", "charlie"]),
            "alpha bravo charlie"
        )
    }

    // MARK: - When there is nothing to quote

    /// The chip is drawn before transcription finishes.
    func testWithNoSegmentsTheSampleIsTheFallbackSentence() {
        XCTAssertEqual(EditorView.previewText(segmentTexts: []), EditorView.fallbackPreviewText)
    }

    /// A segment can exist and hold nothing useful — `split` on an empty or
    /// whitespace-only string yields no words at all.
    func testEmptySegmentsAlsoFallBack() {
        XCTAssertEqual(EditorView.previewText(segmentTexts: [""]), EditorView.fallbackPreviewText)
        XCTAssertEqual(EditorView.previewText(segmentTexts: ["   ", ""]), EditorView.fallbackPreviewText)
    }

    // MARK: - The fallback is a sentence, and there is only one of it

    func testTheFallbackIsASentenceRatherThanAPairOfWords() {
        XCTAssertEqual(EditorView.fallbackPreviewText, "Check out this caption on video")
        XCTAssertEqual(
            EditorView.fallbackPreviewText.split(separator: " ").count,
            StylePreviewCard.maximumSampleWords
        )
    }

    /// There used to be two fallbacks that disagreed: this one, and a
    /// "VIRAL CAPTIONS" literal inside the chip for when it was handed an empty
    /// string. Whichever one a user saw was an accident of timing.
    func testTheChipAndTheEditorFallBackToTheSameString() {
        XCTAssertEqual(
            StylePreviewCard.sampleWords(from: "", isUppercase: false),
            EditorView.fallbackPreviewText.split(separator: " ").map(String.init)
        )
    }

    // MARK: - The seam agrees with what the chip can draw

    func testTheSampleIsNeverLongerThanTheChipWillDraw() {
        let sample = EditorView.previewText(segmentTexts: ["alpha bravo charlie delta echo foxtrot golf hotel"])

        XCTAssertEqual(sample.split(separator: " ").count, StylePreviewCard.maximumSampleWords)
    }
}
