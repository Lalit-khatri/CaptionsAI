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

// MARK: - CaptionOverlay

/// Overlays styled captions on the video player.
/// Supports vertical drag to reposition captions.
struct CaptionOverlay: View {
  let viewModel: EditorViewModel
  let currentTime: Double
  @Binding var yPosition: Double
  let onPositionChanged: (Double) -> Void

  @State private var isDragging = false

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
            .position(
              x: geo.size.width / 2,
              y: geo.size.height * yPosition
            )
            .gesture(
              DragGesture(minimumDistance: kDragMinimumDistance)
                .onChanged { value in
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
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: activeSegment.id)
        .animation(.easeOut(duration: kGuideLineFadeDuration), value: isDragging)
      }
    }
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
