import AVFoundation
import SwiftUI
import CoreImage
import UIKit

// MARK: - Renderer Constants

/// Maximum width fraction of the render area used for caption text
private let kTextMaxWidthFraction: CGFloat = 0.85
/// Base padding around caption text background (in screen points, scaled during export)
private let kTextBackgroundPadding: CGFloat = 12
/// Reference screen width (iPhone logical points) used to compute the export scale factor
private let kReferenceScreenWidth: CGFloat = 393

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
        preferredTransform: CGAffineTransform = .identity
    ) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = outputSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.customVideoCompositorClass = CaptionCompositor.self
        
        // Get video duration
        let duration = try await asset.load(.duration)
        
        // Create instruction covering the full duration
        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            segments: segments,
            style: style,
            renderSize: outputSize,
            captionYPosition: captionYPosition,
            preferredTransform: preferredTransform
        )
        
        // Set up source track ID
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            instruction.requiredSourceTrackIDs = [NSNumber(value: videoTrack.trackID)]
        }
        
        composition.instructions = [instruction]
        return composition
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 1 point = 1 pixel for exact export dimensions
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        
        // Scale font and padding to match export resolution vs screen preview
        let scaleFactor = renderSize.width / kReferenceScreenWidth
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
            
            if style.wordByWordHighlight && !words.isEmpty {
                // Word-by-word highlighting mode
                let attributedString = NSMutableAttributedString()
                
                for word in words {
                    let isActive = currentTime >= word.startTime && currentTime < word.endTime
                    let color = isActive
                        ? UIColor(Color(hex: style.highlightColor.hex))
                        : UIColor(Color(hex: style.textColor.hex))
                    
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let space = attributedString.length > 0 ? " " : ""
                    let displayWord = style.isUppercase ? word.word.uppercased() : word.word
                    attributedString.append(NSAttributedString(string: space + displayWord, attributes: attrs))
                }
                
                drawText(attributedString, in: context, renderSize: renderSize, captionYPosition: captionYPosition, scaleFactor: scaleFactor, style: style)
            } else {
                // Standard text rendering
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(Color(hex: style.textColor.hex)),
                    .paragraphStyle: paragraphStyle
                ]
                
                let displayText = style.isUppercase ? fullText.uppercased() : fullText
                let attributedString = NSAttributedString(string: displayText, attributes: attrs)
                drawText(attributedString, in: context, renderSize: renderSize, captionYPosition: captionYPosition, scaleFactor: scaleFactor, style: style)
            }
        }
        
        guard let cgImage = textImage.cgImage else { return image }
        // Invert Y so UIKit top-left matches CoreImage bottom-left origin
        let textCIImage = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -renderSize.height))
        
        return textCIImage.composited(over: image)
    }
    
    // MARK: - Private Drawing
    
    private static func drawText(
        _ attributedString: NSAttributedString,
        in context: CGContext,
        renderSize: CGSize,
        captionYPosition: Double,
        scaleFactor: CGFloat,
        style: CaptionStyle
    ) {
        let maxWidth = renderSize.width * kTextMaxWidthFraction
        let scaledPadding = kTextBackgroundPadding * scaleFactor
        
        let textRect = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        let yCenter = renderSize.height * captionYPosition
        
        let bgRect = CGRect(
            x: (renderSize.width - textRect.width) / 2 - scaledPadding,
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
            x: (renderSize.width - textRect.width) / 2,
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
    let preferredTransform: CGAffineTransform
    
    init(
        timeRange: CMTimeRange,
        segments: [CaptionSegment],
        style: CaptionStyle,
        renderSize: CGSize,
        captionYPosition: Double,
        preferredTransform: CGAffineTransform = .identity
    ) {
        self.timeRange = timeRange
        self.segments = segments
        self.style = style
        self.renderSize = renderSize
        self.captionYPosition = captionYPosition
        self.preferredTransform = preferredTransform
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
    
    // Disable intermediate caching to prevent Core Image from hoarding GPU textures across frames
    private let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])
    private let renderQueue = DispatchQueue(label: "com.captionsai.compositor")
    
    // Pre-cached black background — created once, reused every frame
    private var cachedBlackBackground: CIImage?
    private var cachedBackgroundSize: CGSize = .zero
    
    // Caption overlay cache — only re-render when the active word or segment changes
    private var cachedCaptionImage: CIImage?
    private var cachedSegmentId: UUID?
    private var cachedActiveWordIndex: Int?
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    
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
              let trackIDNumber = instruction.requiredSourceTrackIDs?.first as? NSNumber else {
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

        // 1. Apply track transform (handles portrait/landscape camera orientation)
        var videoImage = sourceImage.transformed(by: instruction.preferredTransform)

        // Normalize origin so (0,0) is at bottom-left of the bounding box
        let extent = videoImage.extent
        videoImage = videoImage.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )

        // 2. Aspect-fit video into renderSize and center it
        let currentWidth = videoImage.extent.width
        let currentHeight = videoImage.extent.height

        if currentWidth > 0 && currentHeight > 0 {
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
                // Caption visual changed — render a fresh overlay
                let blankImage = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
                cachedCaptionImage = CaptionRenderer.renderCaption(
                    on: blankImage,
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

        // 5. Render to output pixel buffer
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
