import Foundation

// MARK: - Submagic Style Preset

extension CaptionStyle {
    /// Submagic — Signature Submagic AI viral aesthetic.
    /// Modern rounded bold text inside a sleek dark slate pill with electric cyan word highlights.
    static let submagic = CaptionStyle(
        name: "Submagic",
        fontName: "System-Rounded",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#00F0FF"),
        backgroundColor: CodableColor("#0F172A"),
        backgroundOpacity: 0.80,
        cornerRadius: 16,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#00F0FF"),
        isUppercase: true
    )
}
