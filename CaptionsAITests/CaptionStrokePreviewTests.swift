@testable import CaptionsAI
import SwiftUI
import XCTest

/// Whether the editor draws the same outline the file gets.
///
/// The export outlines glyphs properly, via `NSAttributedString`'s
/// `.strokeWidth`. SwiftUI has no text stroke at iOS 17, and the word-by-word
/// caption is a concatenation of `Text` values — a form that only accepts
/// modifiers returning `Text`, which rules out anything that draws. So the
/// preview approximates the outline by dilating the composed view.
///
/// An approximation is fine; an approximation nobody measured is not. These
/// tests measure both renderers and compare.
///
/// What they cannot check is outline *quality* — whether the approximation
/// looks like an outline rather than a smear. Ink bounds are extremal, so a
/// ragged edge and a clean one measure identically. That part is unverified
/// and needs eyes.
@MainActor
final class CaptionStrokePreviewTests: XCTestCase {
    private let size = CGSize(width: 1080, height: 1920)

    private func outlined(wordByWord: Bool) throws -> CaptionStyle {
        var style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: wordByWord))
        style.strokeWidth = 7
        return style
    }

    private func plain(wordByWord: Bool) throws -> CaptionStyle {
        try XCTUnwrap(CaptionInk.plainStyle(wordByWord: wordByWord))
    }

    // MARK: - The preview draws one at all

    func testThePreviewOutlinesPlainCaptions() throws {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)
        let bare = try XCTUnwrap(CaptionInk.previewBounds(style: plain(wordByWord: false), segment: segment, in: size))
        let edged = try XCTUnwrap(CaptionInk.previewBounds(style: outlined(wordByWord: false), segment: segment, in: size))

        XCTAssertGreaterThan(edged.width, bare.width + 2, "the preview drew no outline")
    }

    func testThePreviewOutlinesWordByWordCaptions() throws {
        let segment = CaptionInk.segment(text: "VIRAL CAPTIONS", words: true)
        let bare = try XCTUnwrap(CaptionInk.previewBounds(style: plain(wordByWord: true), segment: segment, in: size))
        let edged = try XCTUnwrap(CaptionInk.previewBounds(style: outlined(wordByWord: true), segment: segment, in: size))

        XCTAssertGreaterThan(edged.width, bare.width + 2, "word-by-word captions got no outline in the preview")
    }

    // MARK: - It matches the file

    /// The editor is a promise about the file. A preview outline visibly
    /// thinner or fatter than the exported one is the same class of defect as
    /// the font-size mismatch this codebase already fixed once.
    func testThePreviewOutlineIsTheSameThicknessAsTheExported() throws {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)

        let previewGrowth = try growth(
            try XCTUnwrap(CaptionInk.previewBounds(style: plain(wordByWord: false), segment: segment, in: size)),
            try XCTUnwrap(CaptionInk.previewBounds(style: outlined(wordByWord: false), segment: segment, in: size))
        )
        let exportGrowth = try growth(
            try XCTUnwrap(CaptionInk.exportBounds(style: plain(wordByWord: false), segment: segment, in: size)),
            try XCTUnwrap(CaptionInk.exportBounds(style: outlined(wordByWord: false), segment: segment, in: size))
        )

        XCTAssertEqual(
            previewGrowth, exportGrowth, accuracy: 4,
            "preview outline \(previewGrowth)px per edge, export \(exportGrowth)px"
        )
    }

    /// One-signed, and stated separately, because the two failures are not
    /// equally bad. An outline thinner in the preview than in the file is a
    /// surprise the user discovers after exporting; the other way round they
    /// simply get slightly less than they saw.
    func testTheExportedOutlineIsNeverThinnerThanThePreviewed() throws {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)

        let previewGrowth = try growth(
            try XCTUnwrap(CaptionInk.previewBounds(style: plain(wordByWord: false), segment: segment, in: size)),
            try XCTUnwrap(CaptionInk.previewBounds(style: outlined(wordByWord: false), segment: segment, in: size))
        )
        let exportGrowth = try growth(
            try XCTUnwrap(CaptionInk.exportBounds(style: plain(wordByWord: false), segment: segment, in: size)),
            try XCTUnwrap(CaptionInk.exportBounds(style: outlined(wordByWord: false), segment: segment, in: size))
        )

        XCTAssertGreaterThanOrEqual(exportGrowth, previewGrowth - 1.5)
    }

    /// Extra ink per edge, in pixels.
    private func growth(_ bare: CGRect, _ edged: CGRect) -> CGFloat {
        (edged.width - bare.width) / 2
    }

    // MARK: - Off means off

    func testAStyleWithNoOutlineIsUntouchedInThePreview() throws {
        let segment = CaptionInk.segment(text: "VIRAL", words: false)
        var zeroed = try plain(wordByWord: false)
        zeroed.strokeWidth = 0

        XCTAssertEqual(
            try XCTUnwrap(CaptionInk.previewBounds(style: zeroed, segment: segment, in: size)),
            try XCTUnwrap(CaptionInk.previewBounds(style: plain(wordByWord: false), segment: segment, in: size))
        )
    }
}
