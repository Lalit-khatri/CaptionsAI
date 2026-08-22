import Foundation

// MARK: - Fire Style Preset

extension CaptionStyle {
    /// Fire — High-hype TikTok Shorts and fitness/motivation caption style.
    /// Bold crimson red uppercase text with blazing gold active word highlights on a dark backdrop.
    static let fire = CaptionStyle(
        name: "Fire",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#FF3B30"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#18181B"),
        backgroundOpacity: 0.85,
        cornerRadius: 12,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#FF3B30"),
        isUppercase: true
    )
}
