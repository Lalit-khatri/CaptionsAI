import Foundation

// MARK: - Nordic Mint Style Preset

extension CaptionStyle {
    /// Nordic Mint — Inspired by OpusClip clean aesthetic and Scandinavian daily vlogs.
    /// Crisp off-white text, soothing pastel mint active highlight with dimmed context,
    /// and a light ambient shadow in the lower third.
    static let nordicMint = CaptionStyle(
        name: "Nordic Mint",
        fontName: "System-Medium",
        fontSize: 26,
        textColor: CodableColor("#F8FAFC"),
        highlightColor: CodableColor("#6EE7B7"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomThird,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#40000000"),
        isUppercase: false,
        maxWidthFraction: 0.70,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .dimInactive
    )
}
