import Foundation

// MARK: - Beast Style Preset

extension CaptionStyle {
    /// Beast — High-energy MrBeast inspired YouTube/Shorts typography.
    /// Bold electric yellow uppercase text with heavy black stroke and neon green active words.
    static let beast = CaptionStyle(
        name: "Beast",
        fontName: "AvenirNext-Heavy",
        fontSize: 34,
        textColor: CodableColor("#FFE600"),
        highlightColor: CodableColor("#39FF14"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
