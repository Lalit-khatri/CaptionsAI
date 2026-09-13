@testable import CaptionsAI
import CoreImage
import SwiftData
import SwiftUI
import UIKit
import XCTest

/// Whether a caption wraps the same way in the editor and in the exported file.
///
/// The defect: `CaptionOverlay.captionText(for:in:)` was handed the player's
/// size and threw it away, so the preview laid its text out across the full
/// width. The export wraps at `kTextMaxWidthFraction` of the frame. A caption
/// that read as one line while editing could ship as two.
///
/// Both paths are rendered here at 393pt wide, which is the reference width
/// the export scales against — at that size the scale factor is 1 and the two
/// use the same font, so their layouts are directly comparable.
@MainActor
final class CaptionWrapTests: XCTestCase {
    private let frameSize = CGSize(width: 393, height: 852)
    private let sentence = "the quick brown fox jumps over the lazy dog while it keeps running"

    override func setUp() {
        super.setUp()
        // The one-time drag hint would otherwise draw a tooltip into the
        // snapshot and count as caption ink.
        UserDefaults.standard.set(true, forKey: "hasSeenCaptionDragHint")
    }

    // MARK: - Fixtures

    /// Hormozi with the background and shadow turned off, so the only ink in
    /// either render is the glyphs themselves.
    private func plainStyle(wordByWord: Bool) throws -> CaptionStyle {
        var style = try XCTUnwrap(CaptionStyle.presets.first { $0.name == "Hormozi" })
        style.backgroundOpacity = 0
        style.shadowRadius = 0
        style.wordByWordHighlight = wordByWord
        return style
    }

    private func makeSegment(words: Bool) -> CaptionSegment {
        let pieces = sentence.split(separator: " ").map(String.init)
        let timings: [WordTiming] = words
            ? pieces.enumerated().map { index, word in
                WordTiming(
                    word: word,
                    startTime: Double(index) * 0.2,
                    endTime: Double(index) * 0.2 + 0.2
                )
            }
            : []
        return CaptionSegment(
            startTime: 0,
            endTime: 10,
            text: sentence,
            sortOrder: 0,
            words: timings
        )
    }

    private func makeViewModel(style: CaptionStyle, segment: CaptionSegment) throws -> EditorViewModel {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        project.segments = [segment]
        context.insert(project)
        try context.save()
        let viewModel = EditorViewModel(project: project, audioSession: FakeAudioSession())
        viewModel.selectStyle(style)
        return viewModel
    }

    // MARK: - Rendering

    private func previewInk(style: CaptionStyle, segment: CaptionSegment) throws -> CGRect {
        let viewModel = try makeViewModel(style: style, segment: segment)
        let overlay = CaptionOverlay(
            viewModel: viewModel,
            currentTime: 0.1,
            yPosition: .constant(0.5),
            onPositionChanged: { _ in }
        )
        .frame(width: frameSize.width, height: frameSize.height)

        let renderer = ImageRenderer(content: overlay)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "the preview did not render")
        return try inkBounds(of: try XCTUnwrap(image.cgImage))
    }

    private func exportInk(style: CaptionStyle, segment: CaptionSegment) throws -> CGRect {
        let overlay = try XCTUnwrap(
            CaptionRenderer.renderCaptionOverlay(
                segment: segment,
                style: style,
                currentTime: 0.1,
                renderSize: frameSize,
                captionYPosition: 0.5
            ),
            "the export renderer produced nothing"
        )
        let cgImage = try XCTUnwrap(
            CIContext().createCGImage(overlay, from: CGRect(origin: .zero, size: frameSize))
        )
        return try inkBounds(of: cgImage)
    }

    /// The smallest rectangle containing every pixel that was drawn on.
    private func inkBounds(of image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where pixels[(y * width + x) * 4 + 3] > 16 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return .zero }
        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }

    // MARK: - Guards
    //
    // If either renderer is broken, everything below fails for reasons that
    // have nothing to do with wrapping. These say which.

    func testThePreviewRendererDrawsSomething() throws {
        let style = try plainStyle(wordByWord: true)
        let ink = try previewInk(style: style, segment: makeSegment(words: true))

        XCTAssertGreaterThan(ink.width, frameSize.width * 0.2, "the preview drew no caption")
        XCTAssertGreaterThan(ink.height, 0)
    }

    func testTheExportRendererDrawsSomething() throws {
        let style = try plainStyle(wordByWord: true)
        let ink = try exportInk(style: style, segment: makeSegment(words: true))

        XCTAssertGreaterThan(ink.width, frameSize.width * 0.2, "the export drew no caption")
        XCTAssertGreaterThan(ink.height, 0)
    }

    // MARK: - The preview respects the same margin as the export

    func testTheExportKeepsCaptionsInsideTheTextMargin() throws {
        let ink = try exportInk(style: try plainStyle(wordByWord: true), segment: makeSegment(words: true))

        XCTAssertLessThanOrEqual(ink.width, frameSize.width * kTextMaxWidthFraction + 2)
    }

    func testThePreviewKeepsCaptionsInsideTheSameTextMargin() throws {
        let ink = try previewInk(style: try plainStyle(wordByWord: true), segment: makeSegment(words: true))

        XCTAssertLessThanOrEqual(
            ink.width,
            frameSize.width * kTextMaxWidthFraction + 2,
            "the preview ran \(ink.width)pt wide, past the \(frameSize.width * kTextMaxWidthFraction)pt the export wraps at"
        )
    }

    // MARK: - The two agree

    func testAWordByWordCaptionWrapsIntoTheSameShapeInBoth() throws {
        let style = try plainStyle(wordByWord: true)
        let segment = makeSegment(words: true)

        let preview = try previewInk(style: style, segment: segment)
        let export = try exportInk(style: style, segment: segment)

        XCTAssertEqual(
            preview.height,
            export.height,
            accuracy: style.fontSize / 2,
            "the editor shows \(preview.height)pt of caption, the file has \(export.height)pt — a different number of lines"
        )
    }

    func testAPlainCaptionWrapsIntoTheSameShapeInBoth() throws {
        let style = try plainStyle(wordByWord: false)
        let segment = makeSegment(words: false)

        let preview = try previewInk(style: style, segment: segment)
        let export = try exportInk(style: style, segment: segment)

        XCTAssertEqual(
            preview.height,
            export.height,
            accuracy: style.fontSize / 2,
            "the editor shows \(preview.height)pt of caption, the file has \(export.height)pt — a different number of lines"
        )
    }
}
