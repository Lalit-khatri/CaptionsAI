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

    /// The chip is exactly its plate, whatever it is asked to draw.
    func testAShortSampleGivesAChipTheWidthOfItsPlate() throws {
        let width = try size(preset("Cinema"), "A B").width

        XCTAssertEqual(width, StylePreviewCard.plateWidth, accuracy: 0.5)
    }

    func testTheChipIsBigEnoughToReadASentenceIn() {
        XCTAssertGreaterThanOrEqual(StylePreviewCard.plateWidth, 140)
        XCTAssertGreaterThanOrEqual(StylePreviewCard.plateHeight, 96)
    }

    /// Two chips and a sliver of a third is the signal that the row scrolls.
    /// Wider than this and the second chip is the last thing on a small phone,
    /// which reads as a two-item list rather than a scroller.
    func testTwoChipsAndAPeekFitOnTheNarrowestPhone() {
        let screen: CGFloat = 375
        let row = StylePreviewCard.plateWidth * 2 + 12 + 32

        XCTAssertLessThan(row, screen, "two chips no longer fit on a 375pt screen")
        XCTAssertGreaterThan(row + StylePreviewCard.plateWidth, screen, "a third chip fits entirely — no peek")
    }

    // MARK: - The defect this unit existed to make visible

    /// Was: `.frame(width:height:)` sat on the plate, a *sibling* of the text
    /// inside the ZStack, so it constrained the plate and nothing else. A
    /// horizontal `ScrollView` proposes unbounded width, the text took its full
    /// single-line ideal width, and the ZStack — along with the rounded corners
    /// and the selection ring applied to it — grew with the sample.
    ///
    /// The text now carries its own width, so the chip is a constant.
    func testALongSampleNoLongerStretchesTheChip() throws {
        let width = try size(preset("Cinema"), "EXTRAORDINARY UNBELIEVABLE MAGNIFICENT SPECTACULAR").width

        XCTAssertEqual(width, StylePreviewCard.plateWidth, accuracy: 0.5)
    }

    /// The corollary, stated separately so a regression shows up as two
    /// failures and not one: chip width must not be a function of the sample.
    func testTwoDifferentSamplesGiveTheSameChipWidth() throws {
        let style = try preset("Cinema")

        XCTAssertEqual(
            try size(style, "A B").width,
            try size(style, "A MUCH WIDER SAMPLE THAN THAT ONE").width,
            accuracy: 0.5
        )
    }

    // MARK: - How much of the sample survives

    /// The sixth word changing the pixels is also the proof that the sample
    /// wraps. A chip that clipped to one line would hide the tail of the
    /// sentence, and these two renders would be identical.
    func testTheSixthWordIsDrawn() throws {
        let style = try preset("Cinema")

        XCTAssertNotEqual(
            try pixels(style, "ONE TWO THREE FOUR FIVE SIX"),
            try pixels(style, "ONE TWO THREE FOUR FIVE ZETA")
        )
    }

    /// There is still a limit; a whole transcript would scale to nothing.
    func testNothingPastTheSixthWordIsDrawn() throws {
        let style = try preset("Cinema")

        XCTAssertEqual(
            try pixels(style, "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT"),
            try pixels(style, "ONE TWO THREE FOUR FIVE SIX ALPHA BETA"),
            "the chip now draws more than six words"
        )
    }

    func testTheThirdWordIsDrawn() throws {
        let style = try preset("Cinema")

        XCTAssertNotEqual(try pixels(style, "ONE TWO THREE"), try pixels(style, "ONE TWO GAMMA"))
    }

    /// With no words at all the chip substitutes the same sentence the editor
    /// would have handed it. There used to be a second, disagreeing literal
    /// here.
    func testAnEmptySampleFallsBackToTheSharedSentence() throws {
        let style = try preset("Cinema")

        XCTAssertEqual(try pixels(style, ""), try pixels(style, EditorView.fallbackPreviewText))
        XCTAssertNotEqual(try pixels(style, ""), try pixels(style, "VIRAL CAPTIONS"))
    }
}
