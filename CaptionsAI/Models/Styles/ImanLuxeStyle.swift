import Foundation

// MARK: - Iman Luxe Style Preset

extension CaptionStyle {
    /// Iman Luxe — Inspired by Iman Gadzhi and high-ticket luxury/agency creator reels.
    /// Clean geometric uppercase typography, champagne gold highlight, dimmed inactive context,
    /// and wide ambient shadow.
    static let imanLuxe = CaptionStyle(
        name: "Iman Luxe",
        fontName: "AvenirNext-Heavy",
        fontSize: 26,
        textColor: CodableColor("#F8F9FA"),
        highlightColor: CodableColor("#D4AF37"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 10,
        shadowColor: CodableColor("#80000000"),
        isUppercase: true,
        maxWidthFraction: 0.70,
        horizontalOffsetFraction: 0.0,
        wordHighlightEffect: .dimInactive
    )
}
