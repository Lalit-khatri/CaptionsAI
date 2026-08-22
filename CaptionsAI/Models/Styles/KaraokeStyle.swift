import Foundation

// MARK: - Karaoke Style Preset

extension CaptionStyle {
    /// Karaoke — CapCut's #1 viral karaoke template.
    /// Soft grey text where the active spoken word pops into bright royal electric blue.
    static let karaoke = CaptionStyle(
        name: "Karaoke",
        fontName: "System-Heavy",
        fontSize: 32,
        textColor: CodableColor("#94A3B8"),
        highlightColor: CodableColor("#3B82F6"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
