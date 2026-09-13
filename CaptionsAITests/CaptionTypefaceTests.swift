@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// Which typeface a caption is drawn in.
///
/// The defect: the export resolves the declared name with `UIFont(name:)`
/// first and only falls back to reading a weight out of it, but the preview
/// did the opposite. "AvenirNext-Heavy" contains "Heavy", so the preview
/// matched the weight branch, threw the face away and drew the system font —
/// while the exported file was set in Avenir Next. The Beast preset looked
/// like every other heavy preset on screen and like something else entirely
/// in the finished video.
final class CaptionTypefaceTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    // MARK: - The preview and the export agree

    /// `uiFontScaled(to:)` is what the renderer draws the exported file with.
    /// Wherever it resolves a real typeface, the preview has to ask for the
    /// same one.
    func testEveryPresetPreviewsTheTypefaceItExports() {
        for style in CaptionStyle.presets {
            guard let exported = UIFont(name: style.fontName, size: style.fontSize) else { continue }
            XCTAssertEqual(
                style.font, .custom(style.fontName, size: style.fontSize),
                "\(style.name) exports \(exported.familyName) but previews a system face"
            )
        }
    }

    func testBeastIsSetInAvenirNext() throws {
        let beast = try preset("Beast")

        XCTAssertEqual(beast.fontName, "AvenirNext-Heavy")
        XCTAssertEqual(beast.uiFont.familyName, "Avenir Next", "the exported file")
        XCTAssertEqual(beast.font, .custom("AvenirNext-Heavy", size: beast.fontSize), "the preview")
    }

    /// Avenir Next Heavy is already heavy. Asking SwiftUI for a weight on top
    /// of a named face is how it gets replaced by a system font.
    func testANamedFaceIsNotGivenAWeight() throws {
        XCTAssertNil(try preset("Beast").weight)
    }

    // MARK: - The System-* names are not typefaces

    /// The whole reordering rests on this: if any `System-*` name resolved to
    /// a real face, answering `UIFont(name:)` first would change all nine of
    /// the other presets rather than just Beast.
    func testTheSystemPseudoNamesAreNotRealTypefaces() {
        for name in ["System-Heavy", "System-Bold", "System-Medium", "System-Light", "System-Rounded"] {
            XCTAssertNil(UIFont(name: name, size: 32), "\(name) resolves to a real typeface")
        }
    }

    func testTheSystemPresetsStillPreviewASystemFont() throws {
        for name in ["Hormozi", "Cinema", "Ali Abdaal"] {
            let style = try preset(name)
            XCTAssertNotNil(style.weight, "\(name) lost its system weight")
        }
    }
}
