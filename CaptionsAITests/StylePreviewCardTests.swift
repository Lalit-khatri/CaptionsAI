@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// What the chip in the style picker actually draws.
///
/// The defect: the chip built its own font from the style's font *name* —
/// a third copy of a ladder that already existed on `CaptionStyle` and in the
/// export renderer, and the only one whose fallback weight was `.medium`. So
/// the two rounded presets were advertised medium in the picker and drawn
/// heavy everywhere else, and Beast was advertised in the system font and
/// exported in Avenir Next.
///
/// Asserting on `style.font(size:)` alone would not show that the chip *asks*
/// for it, so these render the chip and compare pixels.
@MainActor
final class StylePreviewCardTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    private func render(_ style: CaptionStyle) throws -> Data {
        let card = StylePreviewCard(style: style, isSelected: false, previewText: "VIRAL CAPTIONS")
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "the chip did not render")
        return try XCTUnwrap(image.pngData(), "the chip rendered no pixels")
    }

    // MARK: - The comparisons below mean nothing unless rendering is stable

    func testTwoRendersOfTheSameChipAreIdentical() throws {
        let beast = try preset("Beast")

        XCTAssertEqual(try render(beast), try render(beast))
    }

    func testTheChipDistinguishesTwoDifferentPresets() throws {
        XCTAssertNotEqual(try render(preset("Hormozi")), try render(preset("Cinema")))
    }

    // MARK: - The chip draws the style, not a guess at the style

    /// A chip that ignores the typeface and asks for a system heavy font is
    /// pixel-identical to a chip for a style that really is a system heavy
    /// font. That is exactly what the old ladder produced.
    func testTheChipDrawsBeastInItsOwnTypeface() throws {
        let beast = try preset("Beast")
        var systemTwin = beast
        systemTwin.fontName = "System-Heavy"

        XCTAssertNotEqual(
            try render(beast), try render(systemTwin),
            "the chip draws Beast in the system font, not Avenir Next"
        )
    }

    /// Cinema's highlight colour is the same gold as its text, so if the
    /// highlighted word is drawn at the same weight as the rest, switching
    /// the highlight on changes nothing at all — which is what the old chip
    /// did, having no weight override.
    func testTheChipDrawsTheHighlightedWordHeavier() throws {
        let plain = try preset("Cinema")
        XCTAssertFalse(plain.wordByWordHighlight, "precondition")
        XCTAssertEqual(plain.highlightColor.color, plain.textColor.color, "precondition")

        var highlighted = plain
        highlighted.wordByWordHighlight = true

        XCTAssertNotEqual(
            try render(plain), try render(highlighted),
            "the chip draws the highlighted word at the same weight as the rest"
        )
    }
}
