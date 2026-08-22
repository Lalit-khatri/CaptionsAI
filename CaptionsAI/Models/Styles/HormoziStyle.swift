import Foundation

// MARK: - Hormozi Style Preset

extension CaptionStyle {
    /// Hormozi — White bold text with word-by-word yellow highlight on a black
    /// background box, center position. Inspired by Alex Hormozi's Reels/podcast
    /// caption style that dominates short-form content.
    static let hormozi = CaptionStyle(
        name: "Hormozi",
        fontName: "System-Bold",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.85,
        cornerRadius: 10,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 2,
        shadowColor: CodableColor("#000000")
    )
}
