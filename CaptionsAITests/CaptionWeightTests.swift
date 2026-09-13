@testable import CaptionsAI
import SwiftUI
import XCTest

/// What weight a caption word is drawn at.
///
/// The defect: the word-by-word overlay set `.font(style.font)` — which
/// already carries the weight — and then overrode it with
/// `.fontWeight(isActive ? .heavy : (name contains "Bold" || "Heavy" ? .bold
/// : .regular))`. That second guess re-derived the weight from the font
/// *name*, and disagreed with the style:
///
/// - "System-Rounded" contains neither word, so every unhighlighted word in
///   Ali Abdaal and Submagic was drawn `.regular` — against a heavy preview
///   everywhere else and a heavy exported file.
/// - "System-Heavy" matched the `.bold` branch, so the five heavy presets
///   drew one step lighter than they declare.
///
/// The export renderer never had the second guess, so the preview and the
/// file disagreed.
final class CaptionWeightTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    // MARK: - Unhighlighted words use the style's own weight

    func testARoundedPresetIsNotDrawnRegular() throws {
        for name in ["Ali Abdaal", "Submagic"] {
            let style = try preset(name)
            XCTAssertEqual(style.weight(highlighted: false), .heavy, "\(name)")
        }
    }

    /// Beast is absent deliberately: it names a real typeface, so it is drawn
    /// in that face rather than at a system weight. See `CaptionTypefaceTests`.
    func testAHeavyPresetIsDrawnHeavy() throws {
        for name in ["Hormozi", "Fire", "Cyber Glow", "Karaoke", "Outline", "Vox Box"] {
            let style = try preset(name)
            XCTAssertEqual(style.weight(highlighted: false), .heavy, "\(name)")
        }
    }

    func testAMediumPresetIsDrawnMedium() throws {
        XCTAssertEqual(try preset("Cinema").weight(highlighted: false), .medium)
    }

    func testNoPresetIsDrawnRegular() {
        for style in CaptionStyle.presets {
            XCTAssertNotEqual(
                style.weight(highlighted: false), .regular,
                "\(style.name) draws its unhighlighted words at regular"
            )
        }
    }

    // MARK: - The highlight is still heavier

    func testAHighlightedWordIsHeavy() {
        for style in CaptionStyle.presets {
            XCTAssertEqual(style.weight(highlighted: true), .heavy, "\(style.name)")
        }
    }

    // MARK: - A typeface that carries its own weight is left alone

    func testACustomFaceIsNotGivenAWeight() {
        for face in ["Menlo", "AvenirNext-Regular"] {
            var style = CaptionStyle.hormozi
            style.fontName = face

            XCTAssertNil(style.weight, "imposing a weight on \(face) overrides the face")
        }
    }

    func testACustomFaceIsStillAskedForByName() {
        var style = CaptionStyle.hormozi
        style.fontName = "AvenirNext-Regular"

        XCTAssertEqual(style.font, .custom("AvenirNext-Regular", size: style.fontSize))
    }

    // MARK: - The rounded presets keep their rounded design

    func testARoundedPresetKeepsItsDesign() throws {
        for name in ["Ali Abdaal", "Submagic"] {
            let style = try preset(name)
            XCTAssertEqual(
                style.font,
                .system(size: style.fontSize, weight: .heavy, design: .rounded),
                "\(name)"
            )
        }
    }
}

