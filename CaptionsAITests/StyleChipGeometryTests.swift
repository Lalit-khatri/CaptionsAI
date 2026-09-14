@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// How big the style chip actually is, and how much of the sample it shows.
///
/// These are characterisation tests: they record today's geometry so that the
/// commit which enlarges the chip has to state, in its own diff, exactly which
/// of these numbers it is changing. Several of them pin behaviour that is
/// *wrong* — that is deliberate and flagged inline. A test that pins a defect
/// is how you find out the defect is gone.
@MainActor
final class StyleChipGeometryTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    private func card(_ style: CaptionStyle, _ text: String) -> StylePreviewCard {
        StylePreviewCard(style: style, isSelected: false, previewText: text)
    }

    private func size(_ style: CaptionStyle, _ text: String) throws -> CGSize {
        let renderer = ImageRenderer(content: card(style, text))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "the chip did not render").size
    }

    private func pixels(_ style: CaptionStyle, _ text: String) throws -> Data {
        let renderer = ImageRenderer(content: card(style, text))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "the chip did not render")
        return try XCTUnwrap(image.pngData(), "the chip rendered no pixels")
    }

    // MARK: - The plate

    /// 104x64 is the literal on the `RoundedRectangle`. When the sample is
    /// short enough to fit, the whole chip is that wide.
    func testAShortSampleGivesAChipTheWidthOfItsPlate() throws {
        let width = try size(preset("Cinema"), "A B").width

        XCTAssertEqual(width, 104, accuracy: 0.5)
    }

    // MARK: - The defect this unit exists to make visible

    /// The `.frame(width: 104, height: 64)` is on the plate, which is a
    /// *sibling* of the text inside the ZStack — so it constrains the plate and
    /// nothing else. A horizontal `ScrollView` proposes unbounded width, the
    /// text takes its full single-line ideal width, and the ZStack grows with
    /// it. The rounded corners and the selection ring are applied to the ZStack,
    /// so they grow too: the chip is simply a wider chip, not a clipped one.
    ///
    /// This is why the chip keeps only three words. When the chip is rebuilt to
    /// constrain its text, this assertion must be inverted, not deleted.
    func testTodayALongSampleMakesTheWholeChipWiderThanItsPlate() throws {
        let width = try size(preset("Cinema"), "EXTRAORDINARY UNBELIEVABLE MAGNIFICENT").width

        XCTAssertGreaterThan(
            width, 104,
            "the chip now constrains its text — invert this test and raise the word count"
        )
    }

    /// The corollary, stated separately so a fix shows up as two failures and
    /// not one: chip width is a function of the sample text today. It should be
    /// a constant.
    func testTodayTwoDifferentSamplesGiveTwoDifferentChipWidths() throws {
        let style = try preset("Cinema")

        XCTAssertNotEqual(try size(style, "A B").width, try size(style, "WIDER SAMPLE HERE").width)
    }

    // MARK: - How much of the sample survives

    /// `words` keeps `.prefix(3)`. Anything past the third word cannot affect a
    /// single pixel, so a test that varies the fourth word is testing nothing.
    func testOnlyTheFirstThreeWordsAreDrawn() throws {
        let style = try preset("Cinema")

        XCTAssertEqual(
            try pixels(style, "ONE TWO THREE FOUR FIVE SIX"),
            try pixels(style, "ONE TWO THREE ALPHA BETA GAMMA"),
            "the chip now draws more than three words"
        )
    }

    /// ...and the third word does.
    func testTheThirdWordIsDrawn() throws {
        let style = try preset("Cinema")

        XCTAssertNotEqual(try pixels(style, "ONE TWO THREE"), try pixels(style, "ONE TWO GAMMA"))
    }

    /// With no words at all the chip substitutes its own literal rather than
    /// drawing an empty plate. This is a second, independent fallback from the
    /// one on `EditorView`, and the two do not agree on the string.
    func testAnEmptySampleFallsBackToTheChipsOwnLiteral() throws {
        let style = try preset("Cinema")

        XCTAssertEqual(try pixels(style, ""), try pixels(style, "VIRAL CAPTIONS"))
        XCTAssertNotEqual(try pixels(style, ""), try pixels(style, EditorView.fallbackPreviewText))
    }
}
