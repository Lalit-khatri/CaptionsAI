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

// MARK: - Hint Constants

/// Duration (seconds) before the drag hint auto-dismisses
private let kDragHintAutoDismissDelay: Double = 4.0
/// Vertical offset (points) of the hint tooltip from the caption
private let kDragHintVerticalOffset: CGFloat = 40
/// Bounce amplitude (points) for the caption nudge animation
private let kBounceAmplitude: CGFloat = 8
/// Y position threshold — show hint above caption when at or below this fraction
private let kHintFlipThreshold: Double = 0.5
/// UserDefaults key for tracking whether the drag hint has been shown
private let kHasSeenDragHintKey = "hasSeenCaptionDragHint"

// MARK: - CaptionOverlay

/// Overlays styled captions on the video player.
/// Supports vertical drag to reposition captions.
/// Shows a one-time hint to teach users about the drag feature.
struct CaptionOverlay: View {
  let viewModel: EditorViewModel
  let currentTime: Double
  @Binding var yPosition: Double
  let onPositionChanged: (Double) -> Void

  @State private var isDragging = false
  @State private var showDragHint = false
  @State private var bounceOffset: CGFloat = 0

  var body: some View {
    GeometryReader { geo in
      if let activeSegment = viewModel.segments.first(where: { $0.isActive(at: currentTime) }) {

        ZStack {
          // Guide line visible during drag
          if isDragging {
            Rectangle()
              .fill(Color.white.opacity(0.3))
              .frame(height: 1)
              .position(x: geo.size.width / 2, y: geo.size.height * yPosition)
          }

          captionText(for: activeSegment, in: geo.size)
            .offset(y: bounceOffset)
            .position(
              x: geo.size.width / 2,
              y: geo.size.height * yPosition
            )
            .gesture(
              DragGesture(minimumDistance: kDragMinimumDistance)
                .onChanged { value in
                  if showDragHint { dismissHint() }
                  isDragging = true
                  let newY = value.location.y / geo.size.height
                  yPosition = Double(min(max(newY, kMinCaptionY), kMaxCaptionY))
                }
                .onEnded { value in
                  isDragging = false
                  let finalY = value.location.y / geo.size.height
                  let clamped = Double(min(max(finalY, kMinCaptionY), kMaxCaptionY))
                  onPositionChanged(clamped)
                }
            )

          // One-time drag hint
          if showDragHint {
            CaptionDragHintView()
              .position(
                x: geo.size.width / 2,
                y: geo.size.height * yPosition + (yPosition >= kHintFlipThreshold
                    ? -kDragHintVerticalOffset
                    : kDragHintVerticalOffset)
              )
              .onTapGesture {
                dismissHint()
              }
          }
        }
        // Force view recreation when segment content changes
        .id(activeSegment.id.uuidString + activeSegment.text)
        .transition(.opacity)
        .animation(.easeOut(duration: kGuideLineFadeDuration), value: isDragging)
        .onAppear {
          showHintIfNeeded()
        }
      }
    }
  }

  // MARK: - Hint Logic

  private func showHintIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: kHasSeenDragHintKey) else { return }

    // Show tooltip
    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
      showDragHint = true
    }

    // Bounce the caption
    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
      bounceOffset = -kBounceAmplitude
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
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
    UserDefaults.standard.set(true, forKey: kHasSeenDragHintKey)
  }

  // MARK: - Caption Text

  @ViewBuilder
  private func captionText(for segment: CaptionSegment, in size: CGSize) -> some View {
    let style = viewModel.selectedStyle
    if style.wordByWordHighlight {
      wordByWordText(for: segment)
        .captionBackground(style: style)
    } else {
      let displayText = style.isUppercase ? segment.text.uppercased() : segment.text
      Text(displayText)
        .font(style.font)
        .foregroundColor(style.textColor.color)
        .shadow(
          color: style.shadowColor.color,
          radius: style.shadowRadius,
          x: 0, y: 1
        )
        .captionBackground(style: style)
    }
  }

  // MARK: - Word-by-Word

  @ViewBuilder
  private func wordByWordText(for segment: CaptionSegment) -> some View {
    let words = segment.words
    let style = viewModel.selectedStyle
    if words.isEmpty {
      let displayText = style.isUppercase ? segment.text.uppercased() : segment.text
      Text(displayText)
        .font(style.font)
        .foregroundColor(style.textColor.color)
        .multilineTextAlignment(.center)
        .shadow(
          color: style.shadowColor.color,
          radius: style.shadowRadius,
          x: 0, y: 1
        )
    } else {
      formattedWordText(for: segment)
        .multilineTextAlignment(.center)
        .shadow(
          color: style.shadowColor.color,
          radius: style.shadowRadius,
          x: 0, y: 1
        )
    }
  }

  private func formattedWordText(for segment: CaptionSegment) -> Text {
    let style = viewModel.selectedStyle
    var combined = Text("")
    let words = segment.words
    for (index, word) in words.enumerated() {
      let isActive = currentTime >= word.startTime && currentTime < word.endTime
      let displayWord = style.isUppercase ? word.word.uppercased() : word.word
      let wordText = Text(displayWord + (index < words.count - 1 ? " " : ""))
        .font(style.font)
        .foregroundColor(isActive ? style.highlightColor.color : style.textColor.color)
        .fontWeight(isActive ? .heavy : (style.fontName.contains("Bold") || style.fontName.contains("Heavy") ? .bold : .regular))
      combined = combined + wordText
    }
    return combined
  }
}

// MARK: - Caption Background Modifier

extension View {
  func captionBackground(style: CaptionStyle) -> some View {
    padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        Group {
          if style.backgroundOpacity > 0 {
            RoundedRectangle(cornerRadius: style.cornerRadius)
              .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
          }
        }
      )
  }
}
