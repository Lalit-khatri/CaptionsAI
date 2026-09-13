@testable import CaptionsAI
import SwiftUI
import XCTest

/// Whether a caption wraps the same way in the editor and in the exported file.
///
/// The defect: `CaptionOverlay.captionText(for:in:)` was handed the player's
/// size and threw it away, so the preview laid its text out across the full
/// width. The export wraps at `kTextMaxWidthFraction` of the frame. A caption
/// that read as one line while editing could ship as two.
///
/// Both paths are rendered at the reference width, where the export's scale
/// factor is 1 and the two use the same font, so their layouts are directly
/// comparable. Sizes other than the reference width are
/// `CaptionScaleTests`' business.
@MainActor
final class CaptionWrapTests: XCTestCase {
    private let frameSize = CGSize(width: 393, height: 852)
    private let sentence = "the quick brown fox jumps over the lazy dog while it keeps running"

    private func previewInk(wordByWord: Bool) throws -> CGRect {
        let style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: wordByWord))
        let segment = CaptionInk.segment(text: sentence, words: wordByWord)
        return try XCTUnwrap(
            CaptionInk.previewBounds(style: style, segment: segment, in: frameSize),
            "the preview did not render"
        )
    }

    private func exportInk(wordByWord: Bool) throws -> CGRect {
        let style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: wordByWord))
        let segment = CaptionInk.segment(text: sentence, words: wordByWord)
        return try XCTUnwrap(
            CaptionInk.exportBounds(style: style, segment: segment, in: frameSize),
            "the export renderer produced nothing"
        )
    }

    // MARK: - Guards
    //
    // If either renderer is broken, everything below fails for reasons that
    // have nothing to do with wrapping. These say which.

    func testThePreviewRendererDrawsSomething() throws {
        let ink = try previewInk(wordByWord: true)

        XCTAssertGreaterThan(ink.width, frameSize.width * 0.2, "the preview drew no caption")
        XCTAssertGreaterThan(ink.height, 0)
    }

    func testTheExportRendererDrawsSomething() throws {
        let ink = try exportInk(wordByWord: true)

        XCTAssertGreaterThan(ink.width, frameSize.width * 0.2, "the export drew no caption")
        XCTAssertGreaterThan(ink.height, 0)
    }

    // MARK: - The preview respects the same margin as the export

    func testTheExportKeepsCaptionsInsideTheTextMargin() throws {
        let ink = try exportInk(wordByWord: true)

        XCTAssertLessThanOrEqual(ink.width, frameSize.width * kTextMaxWidthFraction + 2)
    }

    func testThePreviewKeepsCaptionsInsideTheSameTextMargin() throws {
        let ink = try previewInk(wordByWord: true)

        XCTAssertLessThanOrEqual(
            ink.width,
            frameSize.width * kTextMaxWidthFraction + 2,
            "the preview ran \(ink.width)pt wide, past the \(frameSize.width * kTextMaxWidthFraction)pt the export wraps at"
        )
    }

    // MARK: - The two agree

    func testAWordByWordCaptionWrapsIntoTheSameShapeInBoth() throws {
        let preview = try previewInk(wordByWord: true)
        let export = try exportInk(wordByWord: true)

        XCTAssertEqual(
            preview.height,
            export.height,
            accuracy: 16,
            "the editor shows \(preview.height)pt of caption, the file has \(export.height)pt — a different number of lines"
        )
    }

    func testAPlainCaptionWrapsIntoTheSameShapeInBoth() throws {
        let preview = try previewInk(wordByWord: false)
        let export = try exportInk(wordByWord: false)

        XCTAssertEqual(
            preview.height,
            export.height,
            accuracy: 16,
            "the editor shows \(preview.height)pt of caption, the file has \(export.height)pt — a different number of lines"
        )
    }
}
