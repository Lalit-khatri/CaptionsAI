@testable import CaptionsAI
import CoreImage
import SwiftData
import SwiftUI
import UIKit

/// Measures what the editor and the export actually draw, so the two can be
/// compared as images rather than as code.
///
/// Both are rendered at a caller-chosen size. At the reference width the
/// export's scale factor is 1, which makes that size the natural control; any
/// other size is where the two are most likely to disagree.
@MainActor
enum CaptionInk {
    /// Hormozi with the background and shadow turned off, so the only ink in
    /// either render is the glyphs themselves.
    static func plainStyle(wordByWord: Bool) -> CaptionStyle? {
        guard var style = CaptionStyle.presets.first(where: { $0.name == "Hormozi" }) else { return nil }
        style.backgroundOpacity = 0
        style.shadowRadius = 0
        style.wordByWordHighlight = wordByWord
        return style
    }

    static func segment(text: String, words: Bool) -> CaptionSegment {
        let pieces = text.split(separator: " ").map(String.init)
        let timings: [WordTiming] = words
            ? pieces.enumerated().map { index, word in
                WordTiming(
                    word: word,
                    startTime: Double(index) * 0.2,
                    endTime: Double(index) * 0.2 + 0.2
                )
            }
            : []
        return CaptionSegment(startTime: 0, endTime: 10, text: text, sortOrder: 0, words: timings)
    }

    // MARK: - The two renderers

    static func previewBounds(style: CaptionStyle, segment: CaptionSegment, in size: CGSize) -> CGRect? {
        // The one-time drag hint would otherwise draw a tooltip into the
        // snapshot and count as caption ink.
        UserDefaults.standard.set(true, forKey: "hasSeenCaptionDragHint")

        guard let container = try? TestSupport.makeInMemoryContainer() else { return nil }
        let context = ModelContext(container)
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        project.segments = [segment]
        context.insert(project)

        let viewModel = EditorViewModel(project: project, audioSession: FakeAudioSession())
        viewModel.selectStyle(style)

        let overlay = CaptionOverlay(
            viewModel: viewModel,
            currentTime: 0.1,
            yPosition: .constant(0.5),
            onPositionChanged: { _ in }
        )
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: overlay)
        renderer.scale = 1
        guard let cgImage = renderer.uiImage?.cgImage else { return nil }
        return bounds(of: cgImage)
    }

    static func exportBounds(style: CaptionStyle, segment: CaptionSegment, in size: CGSize) -> CGRect? {
        guard let overlay = CaptionRenderer.renderCaptionOverlay(
            segment: segment,
            style: style,
            currentTime: 0.1,
            renderSize: size,
            captionYPosition: 0.5
        ) else { return nil }

        guard let cgImage = CIContext().createCGImage(
            overlay,
            from: CGRect(origin: .zero, size: size)
        ) else { return nil }
        return bounds(of: cgImage)
    }

    // MARK: - Pixels

    /// The smallest rectangle containing every pixel that was drawn on.
    static func bounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
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
}
