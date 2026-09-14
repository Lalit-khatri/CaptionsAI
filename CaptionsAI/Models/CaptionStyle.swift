import Foundation
import SwiftUI

// MARK: - CodableColor

/// A Color wrapper that supports Codable via hex string storage.
struct CodableColor: Codable, Hashable {
    let hex: String

    var color: Color {
        Color(hex: hex)
    }

    init(_ hex: String) {
        self.hex = hex
    }

    init(_ color: Color) {
        hex = color.toHex() ?? "#FFFFFF"
    }
}

// MARK: - TextPosition

/// Where captions appear on the video frame.
enum TextPosition: String, Codable, CaseIterable, Hashable {
    case topCenter
    case center
    case bottomCenter
    case bottomThird

    var displayName: String {
        switch self {
        case .topCenter: return "Top"
        case .center: return "Center"
        case .bottomCenter: return "Bottom"
        case .bottomThird: return "Lower Third"
        }
    }

    /// Y position as a fraction of video height (0 = top, 1 = bottom)
    var yPosition: CGFloat {
        switch self {
        case .topCenter: return 0.15
        case .center: return 0.50
        case .bottomCenter: return 0.85
        case .bottomThird: return 0.75
        }
    }
}

// MARK: - AnimationType

/// Animation style for caption appearance.
enum AnimationType: String, Codable, CaseIterable, Hashable {
    case none
    case fadeIn
    case typewriter
    case bounce
    case highlight

    var displayName: String {
        switch self {
        case .none: return "None"
        case .fadeIn: return "Fade In"
        case .typewriter: return "Typewriter"
        case .bounce: return "Bounce"
        case .highlight: return "Highlight"
        }
    }
}

// MARK: - CaptionStyle

/// Defines the visual appearance of captions on video.
struct CaptionStyle: Codable, Identifiable, Hashable {
    var id: String {
        name
    }

    var name: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var highlightColor: CodableColor
    var backgroundColor: CodableColor
    var backgroundOpacity: CGFloat
    var cornerRadius: CGFloat
    var position: TextPosition
    var animation: AnimationType
    var wordByWordHighlight: Bool
    var shadowRadius: CGFloat
    var shadowColor: CodableColor

    /// Outline thickness, as a **percentage of the point size** — not points.
    ///
    /// This is `NSAttributedString.Key.strokeWidth`'s own unit, and keeping it
    /// is what makes the outline correct at every output resolution without
    /// anyone scaling it: the export already scales the font, and a relative
    /// width comes along for the ride. Multiplying it by the render scale
    /// factor as well would make it four times too thick at 4x.
    ///
    /// Zero means no outline. `TextStrokeGateTests` holds the evidence for
    /// both claims.
    var strokeWidth: CGFloat = 0

    var strokeColor: CodableColor = .init("#000000")

    var isUppercase: Bool = false

    // MARK: - SwiftUI Helpers

    /// The weight this style is drawn at, or `nil` when the typeface carries
    /// its own and a weight must not be imposed on top of it.
    ///
    /// ``font`` builds the weight in, but the word-by-word overlay needs it
    /// separately: every run of a concatenated `Text` has to carry the same
    /// modifiers, and the highlighted run overrides the weight. That override
    /// used to be paired with a guess re-derived from the font *name*, which
    /// disagreed with this — "System-Rounded" contains neither "Bold" nor
    /// "Heavy", so every unhighlighted word in the two rounded presets was
    /// drawn `.regular` against a heavy preview elsewhere and a heavy export.
    ///
    /// A name that names a real typeface is answered first, in the same order
    /// ``uiFontScaled(to:)`` uses: the substring ladder is only a way to read
    /// a weight out of the `System-*` pseudo-names, and letting it run first
    /// meant "AvenirNext-Heavy" was read as a weight and the face discarded.
    var weight: Font.Weight? {
        if fontName == "Menlo" { return nil }
        if UIFont(name: fontName, size: fontSize) != nil { return nil }
        if fontName.contains("Rounded") { return .heavy }
        if fontName.contains("Heavy") || fontName.contains("Black") { return .heavy }
        if fontName.contains("Bold") { return .bold }
        if fontName.contains("Light") { return .light }
        if fontName.contains("Medium") { return .medium }
        return .bold
    }

    /// The weight a word is drawn at, highlighted or not.
    ///
    /// The highlight is deliberately heavier than the style; everything else
    /// is the style's own weight.
    func weight(highlighted: Bool) -> Font.Weight? {
        highlighted ? .heavy : weight
    }

    /// A system font at ``weight``, or the named typeface when it carries its
    /// own weight.
    ///
    /// The weight itself is decided in one place, by ``weight``; repeating the
    /// ladder here is what let the two copies disagree.
    var font: Font {
        font(size: fontSize)
    }

    /// The style's font at a size other than its own.
    ///
    /// The chip in the style picker draws every preset at the same small size
    /// so they line up, but it is still previewing *this* style and must ask
    /// for its typeface and weight rather than guessing them again.
    func font(size: CGFloat) -> Font {
        if fontName == "Menlo" {
            return .custom("Menlo-Bold", size: size)
        }
        guard let weight else {
            return .custom(fontName, size: size)
        }
        if fontName.contains("Rounded") {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .system(size: size, weight: weight)
    }

    var uiFont: UIFont {
        uiFontScaled(to: fontSize)
    }

    /// Returns a UIFont matching the style's font family/weight at a custom size.
    /// Used by the export renderer to scale fonts to match the output resolution.
    func uiFontScaled(to size: CGFloat) -> UIFont {
        if let custom = UIFont(name: fontName, size: size) {
            return custom
        }
        if fontName.contains("Rounded") {
            if let descriptor = UIFont.systemFont(ofSize: size, weight: .heavy).fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
        }
        if fontName.contains("Heavy") || fontName.contains("Black") {
            return .systemFont(ofSize: size, weight: .heavy)
        }
        if fontName.contains("Bold") {
            return .systemFont(ofSize: size, weight: .bold)
        }
        if fontName.contains("Light") {
            return .systemFont(ofSize: size, weight: .light)
        }
        if fontName.contains("Medium") {
            return .systemFont(ofSize: size, weight: .medium)
        }
        return .systemFont(ofSize: size, weight: .bold)
    }
}

// MARK: - Style Presets

extension CaptionStyle {
    /// Every caption style the app offers, in picker order (each defined in
    /// its own file in Models/Styles/).
    ///
    /// Order matters twice: it is the order of the style scroller, and the
    /// first entry is what `Project.selectedStyle` falls back to for any
    /// stored name it cannot resolve. New presets are therefore appended
    /// rather than interleaved.
    static let presets: [CaptionStyle] = [
        hormozi,
        beast,
        submagic,
        aliAbdaal,
        glow,
        karaoke,
        cinema,
        fire,
        boldBox,
        outline,
        ticker,
        candy,
        sticker,
        punch,
        terminal,
        editorial,
        focus,
        frosted,
        bubble,
        marker,
    ]
}

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
