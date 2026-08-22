import Foundation

// MARK: - Cinema Style Preset

extension CaptionStyle {
    /// Cinema — Gold-yellow text in a light-weight font at the bottom with a
    /// subtle shadow and no background. The timeless movie subtitle look.
    static let cinema = CaptionStyle(
        name: "Cinema",
        fontName: "System-Light",
        fontSize: 24,
        textColor: CodableColor("#FFD700"),
        highlightColor: CodableColor("#FFD700"),
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
