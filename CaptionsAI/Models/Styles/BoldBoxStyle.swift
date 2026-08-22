import Foundation

// MARK: - Bold Box Style Preset

extension CaptionStyle {
    /// Bold Box — White bold text sitting on a solid black rounded box at the
    /// bottom. The classic YouTube / broadcast subtitle style everyone recognizes.
    static let boldBox = CaptionStyle(
        name: "Bold Box",
        fontName: "System-Bold",
        fontSize: 24,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.85,
        cornerRadius: 8,
        position: .bottomCenter,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000")
    )
}
