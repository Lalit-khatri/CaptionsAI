import Foundation

// MARK: - Marker Style Preset

extension CaptionStyle {
    /// Marker — hand-lettered, warm, lowercase.
    ///
    /// The only informal face in the set. Vlogs, cooking, craft, anything
    /// where a grotesque in caps looks like an advertisement.
    ///
    /// 30pt rather than the 26–28 the other unboxed presets use: script faces
    /// have a small x-height, so they read a size or two smaller than they
    /// measure.
    static let marker = CaptionStyle(
        name: "Marker",
        fontName: "Noteworthy-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFF8E7"),
        highlightColor: CodableColor("#FF6B6B"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomThird,
        animation: .fadeIn,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#B3000000"),
        isUppercase: false
    )
}
