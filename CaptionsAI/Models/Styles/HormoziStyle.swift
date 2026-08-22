import Foundation

// MARK: - Hormozi Style Preset

extension CaptionStyle {
    /// Hormozi — The #1 viral caption style on Reels, TikTok & Shorts.
    /// Bold uppercase text with word-by-word electric lime/yellow highlight on a sleek black box.
    static let hormozi = CaptionStyle(
        name: "Hormozi",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#39FF14"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.85,
        cornerRadius: 12,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 3,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
