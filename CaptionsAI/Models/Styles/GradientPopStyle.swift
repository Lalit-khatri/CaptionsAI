import Foundation

// MARK: - Gradient Pop Style Preset

extension CaptionStyle {
    /// Gradient Pop — Bold white text with a warm glow, near-opaque white
    /// background, and a playful bounce animation. Perfect for high-energy,
    /// colorful content.
    static let gradientPop = CaptionStyle(
        name: "Gradient Pop",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FF6B6B"),
        backgroundColor: CodableColor("#FFFFFF"),
        backgroundOpacity: 0.9,
        cornerRadius: 16,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: false,
        shadowRadius: 10,
        shadowColor: CodableColor("#FF6B6B")
    )
}
