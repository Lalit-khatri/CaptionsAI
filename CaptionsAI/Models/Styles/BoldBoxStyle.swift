import Foundation

// MARK: - Bold Box Style Preset

extension CaptionStyle {
    /// Bold Box — Vox / Bloomberg / YouTube classic broadcast subtitle.
    /// Crisp high-contrast white text on a solid black box at the bottom.
    static let boldBox = CaptionStyle(
        name: "Vox Box",
        fontName: "System-Heavy",
        fontSize: 24,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.95,
        cornerRadius: 6,
        position: .bottomCenter,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
