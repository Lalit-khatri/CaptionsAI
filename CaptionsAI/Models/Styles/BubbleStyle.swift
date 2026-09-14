import Foundation

// MARK: - Bubble Style Preset

extension CaptionStyle {
    /// Bubble — soft rounded letterforms with a hard dark outline.
    ///
    /// Rounded type usually comes on a pill, which makes it friendly but also
    /// makes it a block. Outlining it instead keeps the warmth and gives the
    /// footage back: the caption sits *in* the shot rather than on top of it.
    /// Sentence case for the same reason.
    ///
    /// The outline is near-black rather than black, which keeps it from
    /// looking like a printing error against the rounded curves.
    static let bubble = CaptionStyle(
        name: "Bubble",
        fontName: "System-Rounded",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#00E5FF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 10,
        strokeColor: CodableColor("#0B1020"),
        isUppercase: false
    )
}
