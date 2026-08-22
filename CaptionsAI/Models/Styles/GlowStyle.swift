import Foundation

// MARK: - Glow Style Preset

extension CaptionStyle {
    /// Glow — Bold white text with a strong neon cyan glow effect, no background.
    /// Mimics the look of neon signs floating over video content.
    static let glow = CaptionStyle(
        name: "Glow",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 16,
        shadowColor: CodableColor("#00FFFF")
    )
}
