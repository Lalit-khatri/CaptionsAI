import Foundation

// MARK: - Outline Style Preset

extension CaptionStyle {
    /// Outline — Universal TikTok / Reels high-contrast outline caption.
    /// Bold white uppercase text with a heavy black outline/stroke that stands out on any video.
    static let outline = CaptionStyle(
        name: "Outline",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFE500"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
