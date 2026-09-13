import SwiftUI

// MARK: - Position Constants

/// Minimum drag distance (in points) before repositioning activates
private let kDragMinimumDistance: CGFloat = 10
/// Minimum Y position fraction to prevent captions going off-screen top
private let kMinCaptionY: CGFloat = 0.08
/// Maximum Y position fraction to prevent captions going off-screen bottom
private let kMaxCaptionY: CGFloat = 0.92
/// Duration (seconds) for the guide line fade-out after dragging ends
private let kGuideLineFadeDuration: Double = 0.5

// MARK: - Caption Box Constants

/// Horizontal padding between the caption text and the edge of its background.
private let kCaptionHorizontalPadding: CGFloat = 14
/// Vertical padding between the caption text and the edge of its background.
private let kCaptionVerticalPadding: CGFloat = 8

// MARK: - Hint Constants

/// Duration (seconds) before the drag hint auto-dismisses
private let kDragHintAutoDismissDelay: Double = 4.0
/// Vertical offset (points) of the hint tooltip from the caption
private let kDragHintVerticalOffset: CGFloat = 40
/// Bounce amplitude (points) for the caption nudge animation
private let kBounceAmplitude: CGFloat = 16
/// Y position threshold — show hint above caption when at or below this fraction
private let kHintFlipThreshold: Double = 0.5
/// UserDefaults key for tracking whether the drag hint has been shown
private let kHasSeenDragHintKey = "hasSeenCaptionDragHint"

// MARK: - CaptionOverlay

/// Overlays styled captions on the video player.
/// Supports vertical drag to reposition captions.
/// Shows a one-time hint to teach users about the drag feature.
struct CaptionOverlay: View {
    // MARK: - Position Bounds

    /// Minimum Y position fraction to prevent captions going off-screen top
    static let minCaptionY: Double = 0.08
    /// Maximum Y position fraction to prevent captions going off-screen bottom
    static let maxCaptionY: Double = 0.92
    /// UserDefaults key for tracking whether the drag hint has been shown
    static let hasSeenDragHintKey = "hasSeenCaptionDragHint"

    /// Clamps a Y coordinate fraction to safe on-screen bounds.
    static func clampYPosition(_ y: Double) -> Double {
        min(max(y, minCaptionY), maxCaptionY)
    }

    let viewModel: EditorViewModel
    let currentTime: Double
    @Binding var yPosition: Double
    let onPositionChanged: (Double) -> Void

    @State private var dragY: Double?
    @State private var isDragging = false
    @State private var showDragHint = false
    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let effectiveY = dragY ?? yPosition
            if let activeSegment = viewModel.segments.first(where: { $0.isActive(at: currentTime) }) {
                ZStack {
                    // Guide line visible during drag
                    if isDragging {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                            .position(x: geo.size.width / 2, y: geo.size.height * effectiveY)
                    }

                    captionText(for: activeSegment, in: geo.size)
                        .offset(y: bounceOffset)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * effectiveY
                        )
                        .gesture(
                            DragGesture(minimumDistance: kDragMinimumDistance)
                                .onChanged { value in
                                    if showDragHint {
                                        dismissHint()
                                    }
                                    isDragging = true
                                    let newY = Double(value.location.y / geo.size.height)
                                    dragY = Self.clampYPosition(newY)
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let finalY = Double(value.location.y / geo.size.height)
                                    let clamped = Self.clampYPosition(finalY)
                                    dragY = nil
                                    yPosition = clamped
                                    onPositionChanged(clamped)
                                }
                        )

                    // One-time drag hint
                    if showDragHint {
                        CaptionDragHintView()
                            .position(
                                x: geo.size.width / 2,
                                y: geo.size.height * effectiveY + (effectiveY >= kHintFlipThreshold
                                    ? -kDragHintVerticalOffset
                                    : kDragHintVerticalOffset)
                            )
                            .onTapGesture {
                                dismissHint()
                            }
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: kGuideLineFadeDuration), value: isDragging)
            }
        }
        .onAppear {
            showHintIfNeeded()
        }
    }

    // MARK: - Hint Logic

    private func showHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeenDragHintKey) else { return }

        // Mark as seen immediately so subsequent redraws never re-trigger
        UserDefaults.standard.set(true, forKey: Self.hasSeenDragHintKey)

        // Show tooltip
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            showDragHint = true
        }

        // Bounce the caption
        withAnimation(.spring(response: 0.4, dampingFraction: 0.3)) {
            bounceOffset = -kBounceAmplitude
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.3)) {
                bounceOffset = 0
            }
        }

        // Auto-dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + kDragHintAutoDismissDelay) {
            dismissHint()
        }
    }

    private func dismissHint() {
        guard showDragHint else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            showDragHint = false
        }
        UserDefaults.standard.set(true, forKey: Self.hasSeenDragHintKey)
    }

    // MARK: - Caption Text

    @ViewBuilder
    private func captionText(for segment: CaptionSegment, in size: CGSize) -> some View {
        let style = viewModel.selectedStyle
        // The export draws captions at `style.fontSize` scaled by how wide the
        // frame is against the reference width. The preview used to draw the
        // point size verbatim, so the two matched only on a 393pt-wide player:
        // at twice that, the editor showed a 25pt caption and the file got a
        // 47pt one.
        let scale = captionScale(forWidth: size.width)
        if style.wordByWordHighlight {
            wordByWordText(for: segment, scale: scale)
                .captionBackground(style: style, scale: scale)
                .frame(maxWidth: captionMaxWidth(in: size, scale: scale))
        } else {
            let displayText = style.isUppercase ? segment.text.uppercased() : segment.text
            Text(displayText)
                .font(style.font(size: style.fontSize * scale))
                .foregroundColor(style.textColor.color)
                .multilineTextAlignment(.center)
                .shadow(
                    color: style.shadowColor.color,
                    radius: style.shadowRadius * scale,
                    x: 0, y: 1 * scale
                )
                .captionBackground(style: style, scale: scale)
                .frame(maxWidth: captionMaxWidth(in: size, scale: scale))
        }
    }

    /// How wide the padded caption box may get before its text has to wrap.
    ///
    /// This size used to be discarded, so the preview laid its text out across
    /// the whole player while the export wrapped at `kTextMaxWidthFraction` —
    /// four lines on screen, five in the file.
    ///
    /// The frame bounds the *padded* box, but `kTextMaxWidthFraction` is the
    /// width the export gives the *text*, so the padding is added back. The
    /// frame goes outside `captionBackground` on purpose: constraining the
    /// text first would stretch the background to the full width even behind a
    /// two-word caption.
    private func captionMaxWidth(in size: CGSize, scale: CGFloat) -> CGFloat {
        size.width * kTextMaxWidthFraction + kCaptionHorizontalPadding * scale * 2
    }

    // MARK: - Word-by-Word

    @ViewBuilder
    private func wordByWordText(for segment: CaptionSegment, scale: CGFloat) -> some View {
        let words = segment.words
        let style = viewModel.selectedStyle
        if words.isEmpty {
            let displayText = style.isUppercase ? segment.text.uppercased() : segment.text
            Text(displayText)
                .font(style.font(size: style.fontSize * scale))
                .foregroundColor(style.textColor.color)
                .multilineTextAlignment(.center)
                .shadow(
                    color: style.shadowColor.color,
                    radius: style.shadowRadius * scale,
                    x: 0, y: 1 * scale
                )
        } else {
            formattedWordText(for: segment, scale: scale)
                .multilineTextAlignment(.center)
                .shadow(
                    color: style.shadowColor.color,
                    radius: style.shadowRadius * scale,
                    x: 0, y: 1 * scale
                )
        }
    }

    private func formattedWordText(for segment: CaptionSegment, scale: CGFloat) -> Text {
        let style = viewModel.selectedStyle
        var combined = Text("")
        let words = segment.words
        for (index, word) in words.enumerated() {
            let isActive = currentTime >= word.startTime && currentTime < word.endTime
            let displayWord = style.isUppercase ? word.word.uppercased() : word.word
            let wordText = Text(displayWord + (index < words.count - 1 ? " " : ""))
                .font(style.font(size: style.fontSize * scale))
                .foregroundColor(isActive ? style.highlightColor.color : style.textColor.color)
                .fontWeight(style.weight(highlighted: isActive))
            combined = combined + wordText
        }
        return combined
    }
}

// MARK: - Caption Background Modifier

extension View {
    /// - Parameter scale: how much larger the player is than the reference
    ///   width, so the box grows with the text inside it rather than staying a
    ///   fixed number of points on every device.
    func captionBackground(style: CaptionStyle, scale: CGFloat) -> some View {
        padding(.horizontal, kCaptionHorizontalPadding * scale)
            .padding(.vertical, kCaptionVerticalPadding * scale)
            .background(
                Group {
                    if style.backgroundOpacity > 0 {
                        RoundedRectangle(cornerRadius: style.cornerRadius * scale)
                            .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                    }
                }
            )
    }
}
