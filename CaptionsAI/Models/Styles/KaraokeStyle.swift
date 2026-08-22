import Foundation

// MARK: - Karaoke Style Preset

extension CaptionStyle {
    /// Karaoke — Large bold text with active word highlighted in bright blue.
    /// Word-by-word timing makes it feel like a real karaoke teleprompter.
    static let karaoke = CaptionStyle(
        name: "Karaoke",
        fontName: "System-Bold",
        fontSize: 34,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#4A90FF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000")
    )
}
