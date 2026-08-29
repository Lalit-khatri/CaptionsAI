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
        captionYPosition: Double
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
            captionYPosition: captionYPosition
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
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        
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
        let textCIImage = CIImage(cgImage: cgImage)
        
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
    
    init(
        timeRange: CMTimeRange,
        segments: [CaptionSegment],
        style: CaptionStyle,
        renderSize: CGSize,
        captionYPosition: Double
    ) {
        self.timeRange = timeRange
        self.segments = segments
        self.style = style
        self.renderSize = renderSize
        self.captionYPosition = captionYPosition
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
    
    private let ciContext = CIContext()
    private let renderQueue = DispatchQueue(label: "com.captionsai.compositor")
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            self?.processRequest(request)
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
        
        var sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
        let currentTime = CMTimeGetSeconds(request.compositionTime)
        
        // Find the active caption segment
        if let activeSegment = instruction.segments.first(where: { $0.isActive(at: currentTime) }) {
            sourceImage = CaptionRenderer.renderCaption(
                on: sourceImage,
                segment: activeSegment,
                style: instruction.style,
                currentTime: currentTime,
                renderSize: instruction.renderSize,
                captionYPosition: instruction.captionYPosition
            )
        }
        
        // Render to output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "CaptionCompositor", code: -2))
            return
        }
        
        ciContext.render(sourceImage, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}
