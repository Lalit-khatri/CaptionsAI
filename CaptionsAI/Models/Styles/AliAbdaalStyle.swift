import Foundation

// MARK: - Ali Abdaal Style Preset

extension CaptionStyle {
    /// Ali Abdaal — Clean, modern aesthetic popularized by Ali Abdaal and Opus Clip podcasts.
    /// Elegant rounded font with a subtle slate capsule backing and warm amber keyword highlight.
    static let aliAbdaal = CaptionStyle(
        name: "Ali Abdaal",
        fontName: "System-Rounded",
        fontSize: 26,
        textColor: CodableColor("#F8FAFC"),
        highlightColor: CodableColor("#F59E0B"),
        backgroundColor: CodableColor("#1E293B"),
        backgroundOpacity: 0.70,
        cornerRadius: 14,
        position: .bottomThird,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 2,
        shadowColor: CodableColor("#000000"),
        isUppercase: false
    )
}
