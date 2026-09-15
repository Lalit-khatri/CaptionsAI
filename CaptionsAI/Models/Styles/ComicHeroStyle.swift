import Foundation

// MARK: - Comic Hero Style Preset

extension CaptionStyle {
    /// Comic Hero — Inspired by Submagic "Maya", cartoon reels, and Y2K pop.
    /// Bold rounded yellow display text, turquoise active word with bounce pop,
    /// and an unmistakable 5.0% heavy cartoon border.
    static let comicHero = CaptionStyle(
        name: "Comic Hero",
        fontName: "System-Rounded",
        fontSize: 34,
        textColor: CodableColor("#FFDF00"),
        highlightColor: CodableColor("#00E5FF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 5.0,
        strokeColor: CodableColor("#000000"),
        isUppercase: true,
        maxWidthFraction: 0.70,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .popScale
    )
}
