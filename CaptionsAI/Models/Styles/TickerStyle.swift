import Foundation

// MARK: - Ticker Style Preset

extension CaptionStyle {
    /// Ticker — broadcast lower-third, condensed and urgent.
    ///
    /// The only condensed face in the set, which is the point: at 38pt it
    /// carries about a third more characters per line than any other preset,
    /// so a long sentence stays on one line instead of stacking. The active
    /// word goes breaking-news red rather than the usual yellow-green.
    ///
    /// The shadow is 80% black rather than fully opaque — over bright footage
    /// a solid 5pt blur reads as a muddy halo, and this still separates.
    static let ticker = CaptionStyle(
        name: "Ticker",
        fontName: "AvenirNextCondensed-Heavy",
        fontSize: 38,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FF2D2D"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomThird,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 5,
        shadowColor: CodableColor("#CC000000"),
        isUppercase: true
    )
}
