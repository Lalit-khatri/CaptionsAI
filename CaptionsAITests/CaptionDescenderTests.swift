@testable import CaptionsAI
import SwiftUI
import XCTest

/// Letters that hang below the baseline keep their tails, in the editor and in
/// the exported file alike.
///
/// This started as a suspected defect. `drawText` measures with
/// `boundingRect(with:options:context:)` and draws into exactly that
/// rectangle, fractional height and all; Apple's guidance is to `ceil` a
/// measured size before using it, and the classic symptom of skipping that is
/// a shaved descender on the last line — the tails of g, j, p, q and y.
///
/// These tests were written before any fix, to find out whether the symptom
/// was actually present. It was not: "gypqj" draws measurably taller than
/// "nnnnn" in both engines, and by the same depth in each. The fractional
/// height evidently leaves enough room here. Nothing was changed; the tests
/// stay because the property is real and worth holding, and because the
/// editor-versus-export comparison sits in the family that has produced six
/// genuine bugs already.
@MainActor
final class CaptionDescenderTests: XCTestCase {
    private let frame = CGSize(width: 393, height: 852)

    private func exportInk(_ text: String) throws -> CGRect {
        var style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: false))
        // Uppercase has no descenders at all, which would make the comparison
        // meaningless.
        style.isUppercase = false
        return try XCTUnwrap(
            CaptionInk.exportBounds(
                style: style,
                segment: CaptionInk.segment(text: text, words: false),
                in: frame
            ),
            "the export rendered nothing for \"\(text)\""
        )
    }

    private func previewInk(_ text: String) throws -> CGRect {
        var style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: false))
        style.isUppercase = false
        return try XCTUnwrap(
            CaptionInk.previewBounds(
                style: style,
                segment: CaptionInk.segment(text: text, words: false),
                in: frame
            ),
            "the preview rendered nothing for \"\(text)\""
        )
    }

    // MARK: - Guard

    func testTheTwoWordsAreTheSameLengthOnScreen() throws {
        // If one is much wider than the other they may wrap differently, and a
        // height difference would mean line count rather than descenders.
        let withTails = try exportInk("gypqj")
        let without = try exportInk("nnnnn")

        XCTAssertEqual(withTails.width, without.width, accuracy: without.width * 0.35)
    }

    // MARK: - Descenders survive

    func testTheExportKeepsTheTailsOnItsLetters() throws {
        let withTails = try exportInk("gypqj")
        let without = try exportInk("nnnnn")

        XCTAssertGreaterThan(
            withTails.height,
            without.height,
            "\"gypqj\" drew no taller than \"nnnnn\" — the descenders are being cut off"
        )
    }

    func testTheEditorKeepsTheTailsToo() throws {
        let withTails = try previewInk("gypqj")
        let without = try previewInk("nnnnn")

        XCTAssertGreaterThan(withTails.height, without.height)
    }

    func testTheEditorAndTheExportLoseTheSameAmountOfTail() throws {
        // SwiftUI does its own layout, so if only one of the two clips, the
        // descender depth will differ between them.
        let previewDepth = try previewInk("gypqj").height - previewInk("nnnnn").height
        let exportDepth = try exportInk("gypqj").height - exportInk("nnnnn").height

        XCTAssertEqual(
            exportDepth,
            previewDepth,
            accuracy: 3,
            "the tails are \(previewDepth)pt deep in the editor and \(exportDepth)pt in the file"
        )
    }
}
