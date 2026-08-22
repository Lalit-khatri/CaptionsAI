import Foundation

// MARK: - Glow Style Preset

extension CaptionStyle {
    /// Glow — Captions.ai Cyberpunk Neon aesthetic.
    /// Punchy cyan uppercase text with an intense glowing aura and hot pink highlights.
    static let glow = CaptionStyle(
        name: "Cyber Glow",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#00FFFF"),
        highlightColor: CodableColor("#FF007F"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .fadeIn,
        wordByWordHighlight: true,
        shadowRadius: 18,
        shadowColor: CodableColor("#00FFFF"),
        isUppercase: true
    )
}
