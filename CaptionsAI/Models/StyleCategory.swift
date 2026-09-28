import Foundation

// MARK: - StyleCategory

/// The tabs across the top of the style sheet.
///
/// Derived from a style's name rather than stored on it. The name is what a
/// project persists, so this adds nothing to `CaptionStyle`'s encoded form and
/// cannot break decoding of existing projects. A style whose name is not
/// listed — a future or custom one — simply belongs to no category and still
/// shows under All.
enum StyleCategory: String, CaseIterable, Identifiable {
    /// Big, heavy, all caps: the high-energy creator look.
    case bold
    /// Normal casing, calm and easy to read.
    case clean
    /// The word lighting up as it is spoken is the look itself.
    case karaoke
    /// Playful fonts and boxes.
    case fun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .clean: return "Clean"
        case .karaoke: return "Karaoke"
        case .fun: return "Fun"
        }
    }

    /// Preset names in each category. A tab lists its styles in preset
    /// order, not this order; see `styles(in:from:)`.
    static let members: [StyleCategory: [String]] = [
        .bold: ["Hormozi", "Beast", "Fire", "Outline", "Ticker", "Punch", "Focus", "Power Gym", "Iman Luxe"],
        .clean: ["Ali Abdaal", "Cinema", "Editorial", "Frosted", "Shamani", "Dan Slate", "Side Note", "Nordic Mint"],
        .karaoke: ["Karaoke", "Cyber Glow", "CapCut Pop", "Auto Pill", "Submagic", "Blink Box"],
        .fun: ["Candy", "Sticker", "Bubble", "Comic Hero", "Marker", "Terminal", "Vox Box"],
    ]

    /// The category `style` is listed under, if any.
    static func of(_ style: CaptionStyle) -> StyleCategory? {
        allCases.first { members[$0, default: []].contains(style.name) }
    }

    /// `presets` narrowed to `category`, keeping their order; every preset
    /// when `category` is nil, which is the All tab.
    static func styles(in category: StyleCategory?, from presets: [CaptionStyle] = CaptionStyle.presets) -> [CaptionStyle] {
        guard let category else { return presets }
        return presets.filter { of($0) == category }
    }
}
