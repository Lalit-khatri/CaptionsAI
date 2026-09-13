@testable import CaptionsAI
import SwiftUI
import XCTest

/// Whether a caption is the same size on screen as it is in the file, on a
/// device that is not exactly the reference width.
///
/// The defect: the export scales caption text by `renderSize.width / 393` —
/// 393pt being one particular iPhone's logical width — while the preview drew
/// the style's point size verbatim, whatever the player was. The two agree
/// only on a 393pt-wide video area. On anything wider the editor shows a
/// caption that is proportionally smaller than the one the file gets, and the
/// gap grows with the screen: on an iPad it is roughly double.
///
/// Sizes are exact multiples of the reference width so the expected ratio is a
/// round number.
@MainActor
final class CaptionScaleTests: XCTestCase {
    private let reference = CGSize(width: 393, height: 852)
    private let doubled = CGSize(width: 786, height: 1704)
    private let phrase = "hello there"

    private func preview(in size: CGSize) throws -> CGRect {
        let style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: true))
        let segment = CaptionInk.segment(text: phrase, words: true)
        return try XCTUnwrap(
            CaptionInk.previewBounds(style: style, segment: segment, in: size),
            "the preview did not render at \(size.width)pt"
        )
    }

    private func export(in size: CGSize) throws -> CGRect {
        let style = try XCTUnwrap(CaptionInk.plainStyle(wordByWord: true))
        let segment = CaptionInk.segment(text: phrase, words: true)
        return try XCTUnwrap(
            CaptionInk.exportBounds(style: style, segment: segment, in: size),
            "the export did not render at \(size.width)pt"
        )
    }

    // MARK: - Guards
    //
    // The reference width is the one size at which the old code was right, and
    // the export's own scaling is the behaviour being matched. If either of
    // these fails, the assertions below are measuring something else.

    func testAtTheReferenceWidthTheEditorAndTheFileAlreadyAgreed() throws {
        let preview = try preview(in: reference)
        let export = try export(in: reference)

        XCTAssertEqual(preview.height, export.height, accuracy: 6)
    }

    func testTheExportScalesCaptionsWithTheFrame() throws {
        let small = try export(in: reference)
        let large = try export(in: doubled)

        XCTAssertEqual(
            large.height / small.height,
            2,
            accuracy: 0.15,
            "the export is meant to scale with the frame and did not"
        )
    }

    // MARK: - The preview scales the same way

    func testThePreviewScalesCaptionsWithThePlayer() throws {
        let small = try preview(in: reference)
        let large = try preview(in: doubled)

        XCTAssertEqual(
            large.height / small.height,
            2,
            accuracy: 0.15,
            "the player doubled in width but its caption grew by \(large.height / small.height)×"
        )
    }

    func testAWideEditorDrawsTheSameCaptionAsItsExport() throws {
        let preview = try preview(in: doubled)
        let export = try export(in: doubled)

        XCTAssertEqual(
            preview.height,
            export.height,
            accuracy: export.height * 0.1,
            "the editor draws a \(preview.height)pt caption and the file gets a \(export.height)pt one"
        )
    }

    func testACaptionTakesTheSameShareOfTheScreenAtAnyWidth() throws {
        // What the user actually notices: the caption looks the same size
        // relative to the video, whichever device they are on.
        let narrow = try preview(in: reference)
        let wide = try preview(in: doubled)

        XCTAssertEqual(
            wide.height / doubled.width,
            narrow.height / reference.width,
            accuracy: 0.01,
            "a caption is \(narrow.height / reference.width) of a narrow screen and \(wide.height / doubled.width) of a wide one"
        )
    }
}
