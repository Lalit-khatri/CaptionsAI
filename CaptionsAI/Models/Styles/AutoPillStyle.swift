import Foundation

// MARK: - Auto Pill Style Preset

extension CaptionStyle {
    /// Auto Pill — Inspired by Neha & Ankush auto-captions and Submagic keyword pills.
    /// Active word receives an individual canary yellow rounded pill box with dark text,
    /// while inactive words stay clean white on transparent.
    static let autoPill = CaptionStyle(
        name: "Auto Pill",
        fontName: "System-Heavy",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFE600"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 5,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 3.0,
        strokeColor: CodableColor("#000000"),
        isUppercase: true,
        maxWidthFraction: 0.75,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .pillBox,
        wordHighlightBgColor: CodableColor("#FFE600"),
        wordHighlightTextColor: CodableColor("#000000")
    )
}
