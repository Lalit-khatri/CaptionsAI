import Foundation

// MARK: - Cinema Style Preset

extension CaptionStyle {
    /// Cinema — Timeless movie & documentary subtitle style (Netflix / HBO style).
    /// Classic warm gold-yellow text placed at bottom center with subtle drop shadow.
    static let cinema = CaptionStyle(
        name: "Cinema",
        fontName: "System-Medium",
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
        shadowColor: CodableColor("#000000"),
        isUppercase: false
    )
}
