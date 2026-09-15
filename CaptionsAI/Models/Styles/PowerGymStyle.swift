import Foundation

// MARK: - Power Gym Style Preset

extension CaptionStyle {
    /// Power Gym — Inspired by fitness, powerlifting and high-intensity motivational shorts.
    /// Compact vertical stack (62% width), heavy condensed font, urgent crimson alert with white active pop,
    /// and thick 5.0% black outline.
    static let powerGym = CaptionStyle(
        name: "Power Gym",
        fontName: "System-Heavy",
        fontSize: 36,
        textColor: CodableColor("#FF1744"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#CC000000"),
        strokeWidth: 5.0,
        strokeColor: CodableColor("#000000"),
        isUppercase: true,
        maxWidthFraction: 0.62,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .popScale
    )
}
