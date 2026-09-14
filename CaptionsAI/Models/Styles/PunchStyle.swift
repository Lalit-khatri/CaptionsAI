import Foundation

// MARK: - Punch Style Preset

extension CaptionStyle {
    /// Punch — condensed black caps inside a heavy outline.
    ///
    /// The loudest preset in the set and the one closest to what the big
    /// short-form channels actually ship: no box, no blur, nothing but a thick
    /// black edge holding white letterforms against whatever is behind them.
    /// It is legible over footage that defeats a scrim, because the outline
    /// follows the glyphs instead of covering the frame.
    ///
    /// `strokeWidth` is a percentage of the point size, so 12 stays in
    /// proportion from the phone preview to a 4K export.
    static let punch = CaptionStyle(
        name: "Punch",
        fontName: "HelveticaNeue-CondensedBlack",
        fontSize: 40,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFD60A"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 12,
        strokeColor: CodableColor("#000000"),
        isUppercase: true
    )
}
