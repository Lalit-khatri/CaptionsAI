import Foundation

// MARK: - Candy Style Preset

extension CaptionStyle {
    /// Candy — a solid hot-pink pill with soft rounded letterforms.
    ///
    /// Every other boxed preset uses a dark, semi-transparent plate. This one
    /// is fully opaque and saturated, so the caption reads as a sticker placed
    /// on the video rather than a scrim laid over it.
    ///
    /// No shadow: a blur under a saturated chip reads as dirt around its edge.
    /// The radius is deliberately larger than the box is tall, which clamps to
    /// a true pill on one line. Two lines become one large rounded rectangle —
    /// the renderer draws one plate per caption, not one per line.
    static let candy = CaptionStyle(
        name: "Candy",
        fontName: "ArialRoundedMTBold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFE93D"),
        backgroundColor: CodableColor("#FF2E9F"),
        backgroundOpacity: 1.0,
        cornerRadius: 26,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
