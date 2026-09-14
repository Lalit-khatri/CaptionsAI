import Foundation

// MARK: - Terminal Style Preset

extension CaptionStyle {
    /// Terminal — monospaced, lowercase, phosphor green on a dark plate.
    ///
    /// The developer/tech-explainer look. The lowercase is not an oversight:
    /// caps defeat the whole reference, which is a console window.
    ///
    /// The face is written "Menlo-Bold" in full and never bare "Menlo" — the
    /// bare family name is special-cased into Menlo-Bold for the preview but
    /// resolves to Menlo-Regular in the export, so the two would disagree.
    ///
    /// 22pt because a monospaced advance width is wide and the renderer wraps
    /// at 85% of the frame; anything larger breaks short sentences in two.
    static let terminal = CaptionStyle(
        name: "Terminal",
        fontName: "Menlo-Bold",
        fontSize: 22,
        textColor: CodableColor("#D4D4D8"),
        highlightColor: CodableColor("#4ADE80"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.78,
        cornerRadius: 4,
        position: .bottomThird,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        isUppercase: false
    )
}
