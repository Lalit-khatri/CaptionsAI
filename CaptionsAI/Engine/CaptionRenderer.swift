import AVFoundation
import SwiftUI
import CoreImage
import UIKit

// MARK: - CaptionRenderer

/// Renders styled captions onto video frames using Core Image and Core Graphics.
final class CaptionRenderer {
    
    // MARK: - Composition Builder
    
    /// Builds an AVVideoComposition that overlays captions onto video frames.
    func buildVideoComposition(
        for asset: AVAsset,
        segments: [CaptionSegment],
        style: CaptionStyle,
        outputSize: CGSize
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
            renderSize: outputSize
        )
        
        // Set up source track ID
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            instruction.requiredSourceTrackIDs = [NSValue(value: videoTrack.trackID)]
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
        renderSize: CGSize
    ) -> CIImage {
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        
        let textImage = renderer.image { ctx in
            let context = ctx.cgContext
            
            // Build attributed text
            let words = segment.words
            let fullText = segment.text
            
            // Configure paragraph style
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping
            
            let font = style.uiFont
            
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
                    attributedString.append(NSAttributedString(string: space + word.word, attributes: attrs))
                }
                
                drawText(attributedString, in: context, style: style, renderSize: renderSize)
            } else {
                // Standard text rendering
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(Color(hex: style.textColor.hex)),
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: fullText, attributes: attrs)
                drawText(attributedString, in: context, style: style, renderSize: renderSize)
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
        style: CaptionStyle,
        renderSize: CGSize
    ) {
        let maxWidth = renderSize.width * 0.85
        let textRect = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        let padding: CGFloat = 12
        let bgRect = CGRect(
            x: (renderSize.width - textRect.width) / 2 - padding,
            y: renderSize.height * style.position.yPosition - textRect.height / 2 - padding,
            width: textRect.width + padding * 2,
            height: textRect.height + padding * 2
        )
        
        // Draw background if needed
        if style.backgroundOpacity > 0 {
            let bgColor = UIColor(Color(hex: style.backgroundColor.hex))
                .withAlphaComponent(style.backgroundOpacity)
            context.setFillColor(bgColor.cgColor)
            
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: style.cornerRadius)
            context.addPath(bgPath.cgPath)
            context.fillPath()
        }
        
        // Draw shadow
        if style.shadowRadius > 0 {
            context.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: style.shadowRadius,
                color: UIColor(Color(hex: style.shadowColor.hex)).cgColor
            )
        }
        
        // Draw text
        let textDrawRect = CGRect(
            x: (renderSize.width - textRect.width) / 2,
            y: renderSize.height * style.position.yPosition - textRect.height / 2,
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
    
    init(
        timeRange: CMTimeRange,
        segments: [CaptionSegment],
        style: CaptionStyle,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.segments = segments
        self.style = style
        self.renderSize = renderSize
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
              let firstTrackIDValue = instruction.requiredSourceTrackIDs?.first else {
            request.finish(with: NSError(domain: "CaptionCompositor", code: -1))
            return
        }
        
        var trackID: CMPersistentTrackID = 0
        firstTrackIDValue.getValue(&trackID)
        
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
                renderSize: instruction.renderSize
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
