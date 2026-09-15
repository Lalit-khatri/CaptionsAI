import Foundation

// MARK: - Blink Box Style Preset

extension CaptionStyle {
    /// Blink Box — Inspired by the Blink app's signature inverted yellow keyword boxes.
    /// Active word pops inside a solid bright yellow pill with pitch-black text,
    /// while remaining words stay white with a crisp black outline.
    static let blinkBox = CaptionStyle(
        name: "Blink Box",
        fontName: "System-Rounded",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFEB3B"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 5,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 3.5,
        strokeColor: CodableColor("#000000"),
        isUppercase: true,
        maxWidthFraction: 0.72,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .pillBox,
        wordHighlightBgColor: CodableColor("#FFEB3B"),
        wordHighlightTextColor: CodableColor("#000000")
    )
}
