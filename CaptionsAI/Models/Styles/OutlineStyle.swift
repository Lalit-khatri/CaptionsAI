import Foundation

// MARK: - Outline Style Preset

extension CaptionStyle {
    /// Outline — Universal TikTok / Reels high-contrast outline caption.
    /// Bold white uppercase text with a heavy black outline that stands out on any video.
    ///
    /// The outline is a real stroke, and it is the whole preset. It used to be
    /// an 8pt blurred shadow pretending to be one, which is a different thing:
    /// a blur has no edge, so on bright footage the caption went soft exactly
    /// where it needed to be crisp. The shadow is gone now that the stroke is
    /// here — a halo outside a hard edge only muddies it.
    ///
    /// `strokeWidth` is a percentage of the point size, so 10 is 10% and the
    /// outline stays in proportion at every export resolution.
    static let outline = CaptionStyle(
        name: "Outline",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFE500"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 10,
        strokeColor: CodableColor("#000000"),
        isUppercase: true
    )
}
