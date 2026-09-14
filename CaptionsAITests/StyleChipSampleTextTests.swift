@testable import CaptionsAI
import XCTest

/// The string the style chips draw.
///
/// This is a pure seam over what was a `private var` on `EditorView`, extracted
/// ahead of the change that widens the chip so that the change has something to
/// be measured against. Nothing here asserts that the current answer is a *good*
/// answer — it asserts what the answer is today, so that a later commit which
/// alters it cannot do so silently.
final class StyleChipSampleTextTests: XCTestCase {
    // MARK: - Today's rules, stated out loud

    func testTheSampleIsTheFirstFourWordsOfTheFirstSegment() {
        XCTAssertEqual(
            EditorView.previewText(firstSegmentText: "one two three four five six"),
            "one two three four"
        )
    }

    func testAShorterSegmentIsUsedWhole() {
        XCTAssertEqual(EditorView.previewText(firstSegmentText: "two words"), "two words")
    }

    /// The chip is drawn before transcription finishes, so there is no segment
    /// to read from and the app falls back to a literal.
    func testWithNoSegmentTheSampleIsTheFallbackLiteral() {
        XCTAssertEqual(EditorView.previewText(firstSegmentText: nil), EditorView.fallbackPreviewText)
    }

    /// A segment can exist and still hold nothing useful — `split` on an empty
    /// or whitespace-only string yields no words at all.
    func testAnEmptySegmentAlsoFallsBack() {
        XCTAssertEqual(EditorView.previewText(firstSegmentText: ""), EditorView.fallbackPreviewText)
        XCTAssertEqual(EditorView.previewText(firstSegmentText: "   "), EditorView.fallbackPreviewText)
    }

    /// Pinned because the copy is user-visible and two words is short enough
    /// that it exercises none of the chip's width behaviour.
    func testTheFallbackLiteralIsTwoWords() {
        XCTAssertEqual(EditorView.fallbackPreviewText, "Hello World")
        XCTAssertEqual(EditorView.fallbackPreviewText.split(separator: " ").count, 2)
    }

    // MARK: - The seam agrees with what the chip can use

    /// The chip itself keeps only three words. Handing it four means the fourth
    /// is computed and then thrown away — harmless, but it means a test that
    /// changes the fourth word cannot observe anything, which is worth knowing
    /// before writing one.
    func testTheSampleCanBeLongerThanTheChipWillDraw() {
        let sample = EditorView.previewText(firstSegmentText: "alpha bravo charlie delta echo")

        XCTAssertEqual(sample.split(separator: " ").count, 4)
    }
}
