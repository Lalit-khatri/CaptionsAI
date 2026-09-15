import Foundation

// MARK: - CapCut Pop Style Preset

extension CaptionStyle {
    /// CapCut Pop — Inspired by CapCut viral Hinglish & short-form creator captions.
    /// Tight 2-3 word stack (60% width), heavy rounded typeface, neon green highlight with spring bounce,
    /// and thick 4.5% black stroke.
    static let capCutPop = CaptionStyle(
        name: "CapCut Pop",
        fontName: "System-Rounded",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#39FF14"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000"),
        strokeWidth: 4.5,
        strokeColor: CodableColor("#000000"),
        isUppercase: true,
        maxWidthFraction: 0.60,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .popScale
    )
}
