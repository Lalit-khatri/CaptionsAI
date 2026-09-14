import Foundation

// MARK: - Focus Style Preset

extension CaptionStyle {
    /// Focus — the words either side of the spoken one are dimmed, not
    /// recoloured.
    ///
    /// Every other word-by-word preset marks the active word with a colour.
    /// This one drops the *other* words to 40% instead, so the eye is pulled
    /// along the line by contrast rather than hue. It reads as a spotlight
    /// moving across the sentence and it survives any footage, because it
    /// introduces no colour of its own.
    ///
    /// The two text colours are 8-digit `AARRGGBB`: `#66FFFFFF` is 40% white
    /// and `#FFFFFFFF` is opaque. `Color(hex:)` handles both; note that
    /// `Color.toHex()` only emits six digits, so these values must not be
    /// round-tripped through `CodableColor(_ color:)`.
    static let focus = CaptionStyle(
        name: "Focus",
        fontName: "System-Heavy",
        fontSize: 34,
        textColor: CodableColor("#66FFFFFF"),
        highlightColor: CodableColor("#FFFFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 10,
        shadowColor: CodableColor("#CC000000"),
        isUppercase: true
    )
}
