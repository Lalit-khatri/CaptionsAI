import Foundation

// MARK: - Typewriter Style Preset

extension CaptionStyle {
    /// Typewriter — Menlo monospace font in terminal green on a transparent
    /// background with typewriter animation. Hacker / coding aesthetic.
    static let typewriter = CaptionStyle(
        name: "Typewriter",
        fontName: "Menlo",
        fontSize: 22,
        textColor: CodableColor("#00FF41"),
        highlightColor: CodableColor("#00FF41"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .typewriter,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#00FF41")
    )
}
