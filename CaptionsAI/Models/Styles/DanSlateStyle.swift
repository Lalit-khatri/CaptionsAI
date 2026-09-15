import Foundation

// MARK: - Dan Slate Style Preset

extension CaptionStyle {
    /// Dan Slate — Inspired by Dan Koe and modern thought-leadership reels.
    /// Deep charcoal slate card container, sentence-case modern typography, pure white active word,
    /// and subtle blue underline marker.
    static let danSlate = CaptionStyle(
        name: "Dan Slate",
        fontName: "System-Bold",
        fontSize: 24,
        textColor: CodableColor("#E2E8F0"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#1A1B23"),
        backgroundOpacity: 0.88,
        cornerRadius: 12,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#40000000"),
        isUppercase: false,
        maxWidthFraction: 0.65,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .underline
    )
}
