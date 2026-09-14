import Foundation

// MARK: - Frosted Style Preset

extension CaptionStyle {
    /// Frosted — a pale translucent plate, the light counterpart to every
    /// dark scrim in the set.
    ///
    /// White at 18% over video is not a real blur: the renderer composites
    /// with Core Graphics and has no access to the frame underneath, so a
    /// genuine frosted-glass effect would need the caption layer to sample and
    /// blur what it covers. What this is instead is a soft light wash that
    /// lifts text off dark or busy footage without the hard black rectangle.
    static let frosted = CaptionStyle(
        name: "Frosted",
        fontName: "System-Heavy",
        fontSize: 26,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#A7F3D0"),
        backgroundColor: CodableColor("#FFFFFF"),
        backgroundOpacity: 0.18,
        cornerRadius: 24,
        position: .bottomThird,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 8,
        shadowColor: CodableColor("#99000000"),
        isUppercase: false
    )
}
