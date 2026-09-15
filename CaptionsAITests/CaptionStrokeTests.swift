@testable import CaptionsAI
import CoreImage
import UIKit
import XCTest

/// The export renderer's outline capability.
///
/// One shipped preset uses it — "Outline", which is named after it — and the
/// first assertion here is that the list of presets that outline is exactly
/// the list we meant.
///
/// The interesting one is the scale test. The export renders at up to 4x the
/// preview and multiplies absolute lengths by a scaleFactor derived from the
/// output width. `.strokeWidth` is a percentage of the point size, so it must
/// *not* be multiplied: the font is already being scaled, and scaling the
/// stroke as well compounds the two.
@MainActor
final class CaptionStrokeTests: XCTestCase {
    private func hormozi(strokeWidth: CGFloat) throws -> CaptionStyle {
        var style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: false))
        style.strokeWidth = strokeWidth
        return style
    }

    private func inkWidth(_ style: CaptionStyle, at size: CGSize) throws -> CGFloat {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)
        return try XCTUnwrap(CaptionInk.exportBounds(style: style, segment: segment, in: size)).width
    }

    private func pixels(_ style: CaptionStyle, at size: CGSize) throws -> Data {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)
        let overlay = try XCTUnwrap(CaptionRenderer.renderCaptionOverlay(
            segment: segment,
            style: style,
            currentTime: 0.1,
            renderSize: size,
            captionYPosition: 0.5
        ))
        let cgImage = try XCTUnwrap(
            CIContext().createCGImage(overlay, from: CGRect(origin: .zero, size: size))
        )
        return try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
    }

    // MARK: - Who uses it

    /// Exactly which presets outline is a product decision, so it is written
    /// down. A preset that quietly gains a stroke changes the look of the app
    /// in a commit whose message probably does not say so.
    func testTheOutlinedPresetsAreExactlyTheOnesWeChose() {
        XCTAssertEqual(
            CaptionStyle.presets.filter { $0.strokeWidth > 0 }.map(\.name),
            ["Outline", "Punch", "Bubble", "CapCut Pop"]
        )
    }

    func testAStyleWithNoStrokeRendersExactlyAsItDidBefore() throws {
        let size = CGSize(width: 1080, height: 1920)

        XCTAssertEqual(
            try pixels(hormozi(strokeWidth: 0), at: size),
            try pixels(try XCTUnwrap(CaptionInk.plainStyle(wordByWord: false)), at: size)
        )
    }

    // MARK: - The capability

    func testAnOutlineAddsInkAroundTheGlyphs() throws {
        let size = CGSize(width: 1080, height: 1920)
        let plain = try inkWidth(hormozi(strokeWidth: 0), at: size)
        let outlined = try inkWidth(hormozi(strokeWidth: 7), at: size)

        XCTAssertGreaterThan(outlined, plain + 2, "the outline drew no measurable ink")
    }

    func testTheOutlineColourIsHonoured() throws {
        let size = CGSize(width: 1080, height: 1920)
        var white = try hormozi(strokeWidth: 7)
        white.strokeColor = CodableColor("#FFFFFF")
        var red = try hormozi(strokeWidth: 7)
        red.strokeColor = CodableColor("#FF0000")

        XCTAssertNotEqual(try pixels(white, at: size), try pixels(red, at: size))
    }

    // MARK: - The scale trap

    /// Doubling the output width doubles the font, and therefore doubles the
    /// outline — because the outline is a percentage of the font. If the
    /// renderer also multiplied the stroke by the scale factor the extra ink
    /// would grow by four, not two.
    ///
    /// 393pt is the reference width at which scaleFactor is exactly 1.
    func testTheOutlineIsNotMultipliedByTheRenderScaleFactor() throws {
        let reference = CGSize(width: 393, height: 699)
        let doubled = CGSize(width: 786, height: 1398)

        let atReference = try inkWidth(hormozi(strokeWidth: 7), at: reference)
            - inkWidth(hormozi(strokeWidth: 0), at: reference)
        let atDoubled = try inkWidth(hormozi(strokeWidth: 7), at: doubled)
            - inkWidth(hormozi(strokeWidth: 0), at: doubled)

        XCTAssertGreaterThan(atReference, 1, "no measurable outline at the reference width")
        XCTAssertEqual(
            atDoubled / atReference, 2, accuracy: 0.6,
            """
            the outline did not scale with the font alone: \(atReference) -> \(atDoubled). \
            A ratio near 4 means strokeWidth was multiplied by the render scale factor.
            """
        )
    }

    // MARK: - Word-by-word draws it too

    /// The renderer builds its attributes in two places — one run per word for
    /// highlighted styles, one for the whole line otherwise. A stroke added to
    /// only one of them outlines some presets and not others, with no pattern
    /// a user could discern.
    func testTheOutlineAppliesToWordByWordStylesAsWell() throws {
        let size = CGSize(width: 1080, height: 1920)
        let segment = CaptionInk.segment(text: "VIRAL CAPTIONS", words: true)

        var plain = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: true))
        plain.strokeWidth = 0
        var outlined = plain
        outlined.strokeWidth = 7

        let plainWidth = try XCTUnwrap(
            CaptionInk.exportBounds(style: plain, segment: segment, in: size)
        ).width
        let outlinedWidth = try XCTUnwrap(
            CaptionInk.exportBounds(style: outlined, segment: segment, in: size)
        ).width

        XCTAssertGreaterThan(outlinedWidth, plainWidth + 2, "word-by-word styles got no outline")
    }
}
