import Foundation

// MARK: - Minimal Style Preset

extension CaptionStyle {
    /// Minimal — Small, light-weight white text at the bottom with a subtle
    /// shadow and no background. Clean, cinematic look for professional edits.
    static let minimal = CaptionStyle(
        name: "Minimal",
        fontName: "System-Light",
        fontSize: 22,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#000000")
    )
}
