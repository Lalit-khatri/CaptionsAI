import Foundation

// MARK: - Side Note Style Preset

extension CaptionStyle {
    /// Side Note — A vertical column anchored on the left side of the video.
    /// Compact width (46%) forces text into a tall 1-2 word stack, shifted left (-0.18 offset).
    /// Perfect for podcast guest reactions, commentary, and vertical margins.
    static let sideNote = CaptionStyle(
        name: "Side Note",
        fontName: "System-Heavy",
        fontSize: 24,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#00F0FF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.65,
        cornerRadius: 8,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#80000000"),
        isUppercase: false,
        maxWidthFraction: 0.46,
        horizontalOffsetFraction: -0.18,
        wordHighlightEffect: .colorSwitch
    )
}
