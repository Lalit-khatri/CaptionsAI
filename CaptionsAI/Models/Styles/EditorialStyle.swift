import Foundation

// MARK: - Editorial Style Preset

extension CaptionStyle {
    /// Editorial — a serif, in sentence case, with no box at all.
    ///
    /// The quiet one. Documentary, interview, long-form talking head: contexts
    /// where a shouting caption undercuts what is being said. It is the only
    /// serif in the set and one of the few presets that is not uppercase.
    ///
    /// Georgia rather than Didot: Didot is the more fashionable cut, but its
    /// hairlines break up over compressed video at this size.
    static let editorial = CaptionStyle(
        name: "Editorial",
        fontName: "Georgia-Bold",
        fontSize: 26,
        textColor: CodableColor("#F7F3EA"),
        highlightColor: CodableColor("#E8927C"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomThird,
        animation: .fadeIn,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#B3000000"),
        isUppercase: false
    )
}
