import Foundation

// MARK: - Outline Style Preset

extension CaptionStyle {
    /// Outline — Bold white text with a strong black shadow that creates an
    /// outline / stroke effect. No background, center position. Readable on
    /// any footage.
    static let outline = CaptionStyle(
        name: "Outline",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 6,
        shadowColor: CodableColor("#000000")
    )
}
