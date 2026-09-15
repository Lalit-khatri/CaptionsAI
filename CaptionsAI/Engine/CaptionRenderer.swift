import AVFoundation
import CoreImage
import SwiftUI
import UIKit

// MARK: - Renderer Constants

/// Maximum width fraction of the render area used for caption text.
///
/// Read by both the export renderer below and `CaptionOverlay` — if the
/// preview wraps at a different width from the file, the user lays out a
/// caption they do not get.
let kTextMaxWidthFraction: CGFloat = 0.85
/// Base padding around caption text background (in screen points, scaled during export)
private let kTextBackgroundPadding: CGFloat = 12
/// Reference screen width (iPhone logical points) used to compute the export scale factor
let kReferenceScreenWidth: CGFloat = 393

/// How much to scale caption text and its padding for a render area `width`
/// points across.
///
/// Read by both the export renderer and `CaptionOverlay`. The export has
/// always scaled; the preview used to draw the style's point size verbatim, so
/// the two agreed only on a 393pt-wide video area and the file's captions came
/// out proportionally larger on anything wider.
func captionScale(forWidth width: CGFloat) -> CGFloat {
    max(width, 1) / kReferenceScreenWidth
}

// MARK: - CaptionRenderer

/// Renders styled captions onto video frames using Core Image and Core Graphics.
final class CaptionRenderer {
    // MARK: - Composition Builder

    /// Builds an AVVideoComposition that overlays captions onto video frames.
    func buildVideoComposition(
        for asset: AVAsset,
        segments: [CaptionSegment],
        style: CaptionStyle,
        outputSize: CGSize,
        captionYPosition: Double,
        preferredOrientation: CGImagePropertyOrientation = .up,
        addWatermark: Bool = false
    ) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = outputSize
        composition.customVideoCompositorClass = CaptionCompositor.self

        // Get video duration
        let duration = try await asset.load(.duration)

        let videoTrack = try await asset.loadTracks(withMediaType: .video).first

        // The output used to be pinned to 30 fps whatever came in: a 60 fps
        // clip lost every other frame, and 24 fps film was resampled into
        // judder. Take the source's own rate instead.
        composition.frameDuration = try await Self.frameDuration(of: videoTrack)

        // Create instruction covering the full duration
        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            segments: segments,
            style: style,
            renderSize: outputSize,
            captionYPosition: captionYPosition,
            preferredOrientation: preferredOrientation,
            addWatermark: addWatermark
        )

        // Set up source track ID
        if let videoTrack {
            instruction.requiredSourceTrackIDs = [NSNumber(value: videoTrack.trackID)]
        }

        composition.instructions = [instruction]
        return composition
    }

    // MARK: - Frame rate

    /// Fallback rate for a source that will not say what it is.
    static let fallbackFrameRate: Int32 = 30

    /// Upper bound on a derived rate. A nominal rate is a float the file
    /// supplies; a corrupt one must not turn into a composition asking for
    /// millions of frames a second.
    static let maximumFrameRate: Float = 240

    /// How long one output frame lasts, taken from `track`.
    static func frameDuration(of track: AVAssetTrack?) async throws -> CMTime {
        guard let track else { return CMTime(value: 1, timescale: fallbackFrameRate) }
        let minimum = try await track.load(.minFrameDuration)
        let nominal = try await track.load(.nominalFrameRate)
        return frameDuration(minFrameDuration: minimum, nominalFrameRate: nominal)
    }

    /// How long one output frame lasts, given what a track reports.
    ///
    /// `minFrameDuration` is preferred because it is exact: an NTSC source
    /// reports 1001/30000, which survives here and would be lost to rounding
    /// if it went through the nominal rate as a float. Both are optional in
    /// practice — plenty of files report neither — hence the fallback.
    static func frameDuration(minFrameDuration: CMTime, nominalFrameRate: Float) -> CMTime {
        if minFrameDuration.isValid, !minFrameDuration.isIndefinite, minFrameDuration.seconds > 0 {
            return minFrameDuration
        }
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: fallbackFrameRate)
        }
        let clamped = min(nominalFrameRate, maximumFrameRate)
        return CMTime(value: 1, timescale: CMTimeScale(max(clamped.rounded(), 1)))
    }

    // MARK: - Static Rendering

    /// Renders a caption onto a source image at the given time.
    static func renderCaption(
        on image: CIImage,
        segment: CaptionSegment,
        style: CaptionStyle,
        currentTime: Double,
        renderSize: CGSize,
        captionYPosition: Double
    ) -> CIImage {
        guard let overlay = renderCaptionOverlay(
            segment: segment,
            style: style,
            currentTime: currentTime,
            renderSize: renderSize,
            captionYPosition: captionYPosition
        ) else {
            return image
        }
        return overlay.composited(over: image)
    }

    // MARK: - Watermark

    /// The mark burned into free-tier exports.
    static let watermarkText = "CaptionsAI"

    /// Point size of the watermark for a given render size.
    ///
    /// Tied to the short side so it reads the same at 360p and at 4K. A fixed
    /// size would be a shout on one and invisible on the other.
    static func watermarkFontSize(for renderSize: CGSize) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        return max(shortSide * 0.045, 10)
    }

    /// Where the watermark sits, in CoreImage's bottom-left origin space.
    ///
    /// Bottom-right, inset by a margin that also scales, and clamped so it
    /// stays on screen even on an implausibly small frame.
    static func watermarkRect(for renderSize: CGSize) -> CGRect {
        let fontSize = watermarkFontSize(for: renderSize)
        let margin = fontSize * 0.8
        // Roughly the advance width of the mark at this size. Generous rather
        // than exact: the text is drawn right-aligned within the box, so a box
        // that is a little wide costs nothing and a box that is too narrow
        // would clip.
        let width = min(fontSize * CGFloat(watermarkText.count) * 0.62, renderSize.width - 2 * margin)
        let height = fontSize * 1.3
        return CGRect(
            x: max(renderSize.width - width - margin, margin),
            y: margin,
            width: width,
            height: height
        )
    }

    /// Draws the watermark, or `nil` if it could not be rendered.
    ///
    /// White with a soft shadow, so it survives both a bright and a dark
    /// frame underneath.
    static func renderWatermark(renderSize: CGSize) -> CIImage? {
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        let fontSize = watermarkFontSize(for: renderSize)
        let rect = watermarkRect(for: renderSize)

        let image = renderer.image { ctx in
            let context = ctx.cgContext
            context.setShadow(
                offset: CGSize(width: 0, height: fontSize * 0.05),
                blur: fontSize * 0.25,
                color: UIColor.black.withAlphaComponent(0.6).cgColor
            )

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: paragraph,
            ]

            // UIKit draws top-left; the rect is bottom-left, so flip it.
            let drawRect = CGRect(
                x: rect.minX,
                y: renderSize.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            (watermarkText as NSString).draw(in: drawRect, withAttributes: attributes)
        }

        return CIImage(image: image)
    }

    /// Renders ONLY the caption text as a standalone transparent CIImage.
    /// Use this for caching — the returned image has no compositing baked in,
    /// so it can be safely composited over any video frame without
    /// leaking the Y-flip transform into the output coordinate space.
    static func renderCaptionOverlay(
        segment: CaptionSegment,
        style: CaptionStyle,
        currentTime: Double,
        renderSize: CGSize,
        captionYPosition: Double
    ) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 1 point = 1 pixel for exact export dimensions
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        // Scale font and padding to match export resolution vs screen preview
        let scaleFactor = captionScale(forWidth: renderSize.width)
        let scaledFontSize = style.fontSize * scaleFactor
        let font = style.uiFontScaled(to: scaledFontSize)

        let textImage = renderer.image { ctx in
            let context = ctx.cgContext

            // Build attributed text
            let words = segment.words
            let fullText = segment.text

            // Configure paragraph style
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping

            if style.wordByWordHighlight, !words.isEmpty {
                // Word-by-word highlighting mode
                let attributedString = NSMutableAttributedString()

                for word in words {
                    let isActive = currentTime >= word.startTime && currentTime < word.endTime
                    let isPill = isActive && style.wordHighlightEffect == .pillBox
                    let isPop = isActive && (style.wordHighlightEffect == .popScale || style.animation == .bounce)
                    let isDimmed = !isActive && style.wordHighlightEffect == .dimInactive
                    let isUnderline = isActive && style.wordHighlightEffect == .underline

                    let wordFontSize = isPop ? scaledFontSize * 1.15 : scaledFontSize
                    let wordFont = style.uiFontScaled(to: wordFontSize)

                    let color: UIColor = {
                        if isPill {
                            return UIColor(Color(hex: style.wordHighlightTextColor.hex))
                        } else if isActive {
                            return UIColor(Color(hex: style.highlightColor.hex))
                        } else if isDimmed {
                            return UIColor(Color(hex: style.textColor.hex)).withAlphaComponent(0.42)
                        } else {
                            return UIColor(Color(hex: style.textColor.hex))
                        }
                    }()

                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: wordFont,
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle,
                    ]

                    if isPill {
                        attrs[.backgroundColor] = UIColor(Color(hex: style.wordHighlightBgColor.hex))
                    } else {
                        applyStroke(style, to: &attrs)
                    }

                    if isUnderline {
                        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        attrs[.underlineColor] = UIColor(Color(hex: style.highlightColor.hex))
                    }

                    let space = attributedString.length > 0 ? " " : ""
                    let displayWord = style.isUppercase ? word.word.uppercased() : word.word
                    attributedString.append(NSAttributedString(string: space + displayWord, attributes: attrs))
                }

                drawText(attributedString, in: context, renderSize: renderSize, captionYPosition: captionYPosition, scaleFactor: scaleFactor, style: style)
            } else {
                // Standard text rendering
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(Color(hex: style.textColor.hex)),
                    .paragraphStyle: paragraphStyle,
                ]
                applyStroke(style, to: &attrs)

                let displayText = style.isUppercase ? fullText.uppercased() : fullText
                let attributedString = NSAttributedString(string: displayText, attributes: attrs)
                drawText(attributedString, in: context, renderSize: renderSize, captionYPosition: captionYPosition, scaleFactor: scaleFactor, style: style)
            }
        }

        guard let cgImage = textImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Private Drawing

    /// Adds the outline attributes, if the style has an outline.
    ///
    /// Two things here are deliberate and easy to get wrong.
    ///
    /// The width is **negated**. Positive `strokeWidth` means stroke *instead
    /// of* fill, which produces hollow letters — legible on a still and
    /// invisible over moving video. Negative means fill *and* stroke.
    ///
    /// And it is not multiplied by `scaleFactor`. `strokeWidth` is a
    /// percentage of the point size, and the point size has already been
    /// scaled by the caller; scaling here too would compound them and make the
    /// outline four times too thick at 4x output.
    private static func applyStroke(
        _ style: CaptionStyle,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard style.strokeWidth > 0 else { return }
        attributes[.strokeWidth] = -style.strokeWidth
        attributes[.strokeColor] = UIColor(Color(hex: style.strokeColor.hex))
    }

    private static func drawText(
        _ attributedString: NSAttributedString,
        in context: CGContext,
        renderSize: CGSize,
        captionYPosition: Double,
        scaleFactor: CGFloat,
        style: CaptionStyle
    ) {
        let maxWidth = renderSize.width * style.maxWidthFraction
        let scaledPadding = kTextBackgroundPadding * scaleFactor

        let textRect = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let yCenter = renderSize.height * captionYPosition
        let xCenter = (renderSize.width / 2) + (renderSize.width * style.horizontalOffsetFraction)

        let bgRect = CGRect(
            x: xCenter - textRect.width / 2 - scaledPadding,
            y: yCenter - textRect.height / 2 - scaledPadding,
            width: textRect.width + scaledPadding * 2,
            height: textRect.height + scaledPadding * 2
        )

        // Draw background if needed
        if style.backgroundOpacity > 0 {
            let bgColor = UIColor(Color(hex: style.backgroundColor.hex))
                .withAlphaComponent(style.backgroundOpacity)
            context.setFillColor(bgColor.cgColor)

            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: style.cornerRadius * scaleFactor)
            context.addPath(bgPath.cgPath)
            context.fillPath()
        }

        // Draw shadow
        if style.shadowRadius > 0 {
            context.setShadow(
                offset: CGSize(width: 0, height: 1 * scaleFactor),
                blur: style.shadowRadius * scaleFactor,
                color: UIColor(Color(hex: style.shadowColor.hex)).cgColor
            )
        }

        // Draw text
        let textDrawRect = CGRect(
            x: xCenter - textRect.width / 2,
            y: yCenter - textRect.height / 2,
            width: textRect.width,
            height: textRect.height
        )
        attributedString.draw(in: textDrawRect)
    }
}

// MARK: - CaptionCompositionInstruction

/// Custom video composition instruction that carries caption data.
final class CaptionCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let segments: [CaptionSegment]
    let style: CaptionStyle
    let renderSize: CGSize
    let captionYPosition: Double

    /// How the source frame has to be turned before it is drawn. This is the
    /// only rotation in the pixel path; a `preferredTransform` used to sit
    /// beside it, stored and never read.
    let preferredOrientation: CGImagePropertyOrientation

    /// Whether to burn the free-tier watermark into each frame.
    let addWatermark: Bool

    init(
        timeRange: CMTimeRange,
        segments: [CaptionSegment],
        style: CaptionStyle,
        renderSize: CGSize,
        captionYPosition: Double,
        preferredOrientation: CGImagePropertyOrientation = .up,
        addWatermark: Bool = false
    ) {
        self.timeRange = timeRange
        self.segments = segments
        self.style = style
        self.renderSize = renderSize
        self.captionYPosition = captionYPosition
        self.preferredOrientation = preferredOrientation
        self.addWatermark = addWatermark
        super.init()
    }
}

// MARK: - CaptionCompositor

/// Custom AVVideoCompositing that overlays captions on each video frame.
final class CaptionCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    /// Disable intermediate caching to prevent Core Image from hoarding GPU textures across frames
    private let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])
    private let renderQueue = DispatchQueue(label: "com.captionsai.compositor")

    // Pre-cached black background — created once, reused every frame
    private var cachedBlackBackground: CIImage?
    private var cachedBackgroundSize: CGSize = .zero

    // Caption overlay cache — only re-render when the active word or segment changes
    private var cachedCaptionImage: CIImage?
    private var cachedSegmentId: UUID?
    private var cachedActiveWordIndex: Int?
    private var cachedWatermarkImage: CIImage?
    private var cachedWatermarkSize: CGSize = .zero

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            // autoreleasepool ensures all temporary UIImage, CGImage, CIImage, and
            // CVPixelBuffer allocations are freed immediately after each frame finishes,
            // preventing memory from climbing to 3+ GB during long video exports.
            autoreleasepool {
                self?.processRequest(request)
            }
        }
    }

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CaptionCompositionInstruction,
              let trackIDNumber = instruction.requiredSourceTrackIDs?.first as? NSNumber
        else {
            request.finish(with: NSError(domain: "CaptionCompositor", code: -1))
            return
        }

        let trackID = CMPersistentTrackID(trackIDNumber.int32Value)

        guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: NSError(domain: "CaptionCompositor", code: -1))
            return
        }

        let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
        let currentTime = CMTimeGetSeconds(request.compositionTime)
        let renderSize = instruction.renderSize

        // 1. Turn the frame the way the source file asks. This is the only
        // rotation applied to the pixels.
        var videoImage = sourceImage.oriented(instruction.preferredOrientation)

        // 2. Aspect-fit video into renderSize and center it
        let currentWidth = videoImage.extent.width
        let currentHeight = videoImage.extent.height

        if currentWidth > 0, currentHeight > 0 {
            let scaleX = renderSize.width / currentWidth
            let scaleY = renderSize.height / currentHeight
            let scale = min(scaleX, scaleY)

            let scaledWidth = currentWidth * scale
            let scaledHeight = currentHeight * scale

            let offsetX = (renderSize.width - scaledWidth) / 2.0
            let offsetY = (renderSize.height - scaledHeight) / 2.0

            let fitTransform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

            videoImage = videoImage.transformed(by: fitTransform)
        }

        // 3. Composite over cached black background (created once, reused every frame)
        let blackBackground = getBlackBackground(for: renderSize)
        videoImage = videoImage.composited(over: blackBackground)

        // 4. Overlay active caption segment if present (with caching)
        if let activeSegment = instruction.segments.first(where: { $0.isActive(at: currentTime) }) {
            // Determine which word is currently highlighted (for word-by-word styles)
            let activeWordIndex = activeSegment.words.firstIndex(where: {
                currentTime >= $0.startTime && currentTime < $0.endTime
            })

            // Only re-render the caption bitmap if the segment or active word changed
            if activeSegment.id != cachedSegmentId || activeWordIndex != cachedActiveWordIndex {
                cachedCaptionImage = CaptionRenderer.renderCaptionOverlay(
                    segment: activeSegment,
                    style: instruction.style,
                    currentTime: currentTime,
                    renderSize: renderSize,
                    captionYPosition: instruction.captionYPosition
                )
                cachedSegmentId = activeSegment.id
                cachedActiveWordIndex = activeWordIndex
            }

            // Composite the (possibly cached) caption over the video frame
            if let captionOverlay = cachedCaptionImage {
                videoImage = captionOverlay.composited(over: videoImage)
            }
        } else {
            // No active segment — clear cache
            cachedCaptionImage = nil
            cachedSegmentId = nil
            cachedActiveWordIndex = nil
        }

        // 5. Burn in the free-tier watermark, above the captions so it cannot
        // be hidden behind one. Rendered once per size and reused, like the
        // background — it is identical on every frame.
        if instruction.addWatermark {
            if cachedWatermarkImage == nil || cachedWatermarkSize != renderSize {
                cachedWatermarkImage = CaptionRenderer.renderWatermark(renderSize: renderSize)
                cachedWatermarkSize = renderSize
            }
            if let watermark = cachedWatermarkImage {
                videoImage = watermark.composited(over: videoImage)
            }
        }

        // 6. Render to output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "CaptionCompositor", code: -2))
            return
        }

        ciContext.render(videoImage, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Helpers

    /// Returns a cached black CIImage matching the given size. Created once and reused.
    private func getBlackBackground(for size: CGSize) -> CIImage {
        if let cached = cachedBlackBackground, cachedBackgroundSize == size {
            return cached
        }
        let bg = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        cachedBlackBackground = bg
        cachedBackgroundSize = size
        return bg
    }
}
