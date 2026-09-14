import Foundation

// MARK: - Sticker Style Preset

extension CaptionStyle {
    /// Sticker — near-black text on an opaque white chip.
    ///
    /// The inversion of everything else in the set. Light captions disappear
    /// into bright, blown-out footage — sky, snow, a white studio wall — and
    /// this is the preset for exactly that, where a white outline or a dark
    /// scrim both look like a mistake.
    ///
    /// The shadow must stay at zero. A black blur under near-black glyphs on
    /// white does not separate anything; it just smears the chip.
    static let sticker = CaptionStyle(
        name: "Sticker",
        fontName: "System-Heavy",
        fontSize: 28,
        textColor: CodableColor("#0B0B0F"),
        highlightColor: CodableColor("#7C3AED"),
        backgroundColor: CodableColor("#FFFFFF"),
        backgroundOpacity: 1.0,
        cornerRadius: 10,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000"),
        isUppercase: true
    )
}
