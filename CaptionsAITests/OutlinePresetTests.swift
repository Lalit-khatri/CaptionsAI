@testable import CaptionsAI
import UIKit
import XCTest

/// The preset called "Outline" drew no outline.
///
/// It was a white uppercase caption with an 8pt blurred black shadow and no
/// stroke at all — the shadow standing in for the outline and doing it badly,
/// because a blur spreads evenly in every direction and never produces the
/// hard edge the name promises. Until this commit the renderer had no stroke
/// to offer it; now it does.
///
/// A blur *and* a stroke together is the worst of both: the stroke draws the
/// edge, the blur smears a grey halo outside it and the caption reads as
/// dirty rather than sharp. So the shadow goes as the stroke arrives.
@MainActor
final class OutlinePresetTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    private func inkWidth(_ style: CaptionStyle) throws -> CGFloat {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)
        return try XCTUnwrap(
            CaptionInk.exportBounds(style: style, segment: segment, in: CGSize(width: 1080, height: 1920))
        ).width
    }

    // MARK: - It outlines

    func testTheOutlinePresetDeclaresAnOutline() throws {
        XCTAssertGreaterThan(
            try preset("Outline").strokeWidth, 0,
            "the preset named Outline still has no outline"
        )
    }

    /// Declaring a stroke and drawing one are different things: the renderer
    /// reads `strokeWidth` in two separate attribute dictionaries, and this
    /// preset highlights word by word, so it goes through the per-word one.
    func testTheOutlinePresetDrawsMoreInkThanTheSameStyleWithoutOne() throws {
        let outlined = try preset("Outline")
        var bare = outlined
        bare.strokeWidth = 0

        XCTAssertGreaterThan(
            try inkWidth(outlined), try inkWidth(bare) + 2,
            "the preset declares an outline the renderer does not draw"
        )
    }

    func testTheOutlineIsBlack() throws {
        XCTAssertEqual(try preset("Outline").strokeColor.hex, "#000000")
    }

    // MARK: - And stops pretending with a blur

    func testTheOutlinePresetNoLongerLeansOnABlurredShadow() throws {
        XCTAssertEqual(
            try preset("Outline").shadowRadius, 0,
            "a blurred halo outside a hard stroke reads as dirt"
        )
    }

    // MARK: - Nothing else about it moved

    /// `name` is the persistence key: every project that chose this style
    /// stores the string. The look may change; the name may not.
    ///
    /// Its position is pinned too, because position is the order of the style
    /// scroller — changing the look of a preset is one decision and moving it
    /// somewhere else in the picker is another.
    func testThePresetKeepsItsNameAndItsPlace() {
        XCTAssertEqual(CaptionStyle.presets.firstIndex { $0.name == "Outline" }, 9)
    }

    func testEverythingElseAboutThePresetIsUnchanged() throws {
        let outline = try preset("Outline")

        XCTAssertEqual(outline.fontName, "System-Heavy")
        XCTAssertEqual(outline.fontSize, 32)
        XCTAssertEqual(outline.textColor.hex, "#FFFFFF")
        XCTAssertEqual(outline.highlightColor.hex, "#FFE500")
        XCTAssertEqual(outline.backgroundOpacity, 0, "an outline style has no box")
        XCTAssertEqual(outline.position, .center)
        XCTAssertTrue(outline.wordByWordHighlight)
        XCTAssertTrue(outline.isUppercase)
    }
}
