import Foundation

// MARK: - Fire Style Preset

extension CaptionStyle {
    /// Fire — Bold orange-red text with word-by-word yellow highlight on a dark
    /// semi-transparent background. High-energy style for hype content.
    static let fire = CaptionStyle(
        name: "Fire",
        fontName: "System-Bold",
        fontSize: 32,
        textColor: CodableColor("#FF4500"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#1A1A1A"),
        backgroundOpacity: 0.75,
        cornerRadius: 10,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#FF4500")
    )
}
