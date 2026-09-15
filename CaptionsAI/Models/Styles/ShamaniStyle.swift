import Foundation

// MARK: - Shamani Style Preset

extension CaptionStyle {
    /// Shamani — Inspired by Raj Shamani and high-retention podcast reels.
    /// Compact vertical stack (55% width), clean modern system sans, active word pop scale,
    /// dimmed inactive context, electric yellow highlight.
    static let shamani = CaptionStyle(
        name: "Shamani",
        fontName: "System-Heavy",
        fontSize: 30,
        textColor: CodableColor("#B0B0B8"),
        highlightColor: CodableColor("#FFE600"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#99000000"),
        isUppercase: false,
        maxWidthFraction: 0.55,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .popScale
    )
}
