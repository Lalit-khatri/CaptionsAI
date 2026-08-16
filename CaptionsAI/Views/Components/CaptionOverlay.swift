import SwiftUI

// MARK: - CaptionOverlay

/// Overlays styled captions on the video player.
/// Finds the active segment based on current playback time.
struct CaptionOverlay: View {
    let currentTime: Double
    let segments: [CaptionSegment]
    let style: CaptionStyle
    
    var body: some View {
        GeometryReader { geo in
            if let activeSegment = segments.first(where: { $0.isActive(at: currentTime) }) {
                captionText(for: activeSegment, in: geo.size)
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height * style.position.yPosition
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: activeSegment.id)
            }
        }
    }
    
    // MARK: - Caption Text
    
    @ViewBuilder
    private func captionText(for segment: CaptionSegment, in size: CGSize) -> some View {
        if style.wordByWordHighlight {
            wordByWordText(for: segment)
                .captionBackground(style: style)
        } else {
            Text(segment.text)
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
    
    private func wordByWordText(for segment: CaptionSegment) -> some View {
        let words = segment.words
        
        return HStack(spacing: 4) {
            ForEach(words) { word in
                let isActive = currentTime >= word.startTime && currentTime < word.endTime
                Text(word.word)
                    .font(style.font)
                    .foregroundColor(isActive ? style.highlightColor.color : style.textColor.color)
                    .scaleEffect(isActive ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isActive)
            }
        }
        .shadow(
            color: style.shadowColor.color,
            radius: style.shadowRadius,
            x: 0, y: 1
        )
    }
}

// MARK: - Caption Background Modifier

extension View {
    func captionBackground(style: CaptionStyle) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if style.backgroundOpacity > 0 {
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                    }
                }
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85)
    }
}
