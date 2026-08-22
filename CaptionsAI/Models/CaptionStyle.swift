import SwiftUI
import Foundation

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
        self.hex = color.toHex() ?? "#FFFFFF"
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
    var id: String { name }
    
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
    
    // MARK: - SwiftUI Helpers
    
    var font: Font {
        if fontName == ".SFUI-Regular" || fontName == "System" {
            return .system(size: fontSize)
        } else if fontName == ".SFUI-Bold" || fontName == "System-Bold" {
            return .system(size: fontSize, weight: .bold)
        } else if fontName == ".SFUI-Light" || fontName == "System-Light" {
            return .system(size: fontSize, weight: .light)
        } else {
            return .custom(fontName, size: fontSize)
        }
    }
    
    var uiFont: UIFont {
        if fontName.contains("System") || fontName.contains("SFUI") {
            if fontName.contains("Bold") {
                return .systemFont(ofSize: fontSize, weight: .bold)
            } else if fontName.contains("Light") {
                return .systemFont(ofSize: fontSize, weight: .light)
            }
            return .systemFont(ofSize: fontSize)
        }
        return UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }
}

// MARK: - Style Presets

extension CaptionStyle {
    /// All available caption style presets
    static let presets: [CaptionStyle] = [
        hormozi, glow, karaoke, minimal, boldBox,
        gradientPop, typewriter, cinema, fire, outline
    ]
    
    // MARK: 1. Hormozi
    
    /// Hormozi — White bold text with word-by-word yellow highlight on a black
    /// background box, center position. Inspired by Alex Hormozi's Reels/podcast
    /// caption style that dominates short-form content.
    static let hormozi = CaptionStyle(
        name: "Hormozi",
        fontName: "System-Bold",
        fontSize: 32,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.85,
        cornerRadius: 10,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 2,
        shadowColor: CodableColor("#000000")
    )
    
    // MARK: 2. Glow
    
    /// Glow — Bold white text with a strong neon glow effect, no background.
    /// Mimics the look of neon signs floating over video content.
    static let glow = CaptionStyle(
        name: "Glow",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 16,
        shadowColor: CodableColor("#00FFFF")
    )
    
    // MARK: 3. Karaoke
    
    /// Karaoke — Large bold text with active word highlighted in bright blue.
    /// Word-by-word timing makes it feel like a real karaoke teleprompter.
    static let karaoke = CaptionStyle(
        name: "Karaoke",
        fontName: "System-Bold",
        fontSize: 34,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#4A90FF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000")
    )
    
    // MARK: 4. Minimal
    
    /// Minimal — Small, light-weight white text at the bottom with a subtle
    /// shadow and no background. Clean, cinematic look for professional edits.
    static let minimal = CaptionStyle(
        name: "Minimal",
        fontName: "System-Light",
        fontSize: 22,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#000000")
    )
    
    // MARK: 5. Bold Box
    
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
    
    // MARK: 6. Gradient Pop
    
    /// Gradient Pop — Bold white text with a warm glow, near-opaque white
    /// background, and a playful bounce animation. Perfect for high-energy,
    /// colorful content.
    static let gradientPop = CaptionStyle(
        name: "Gradient Pop",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FF6B6B"),
        backgroundColor: CodableColor("#FFFFFF"),
        backgroundOpacity: 0.9,
        cornerRadius: 16,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: false,
        shadowRadius: 10,
        shadowColor: CodableColor("#FF6B6B")
    )
    
    // MARK: 7. Typewriter
    
    /// Typewriter — Menlo monospace font in terminal green on a transparent
    /// background with typewriter animation. Hacker / coding aesthetic.
    static let typewriter = CaptionStyle(
        name: "Typewriter",
        fontName: "Menlo",
        fontSize: 22,
        textColor: CodableColor("#00FF41"),
        highlightColor: CodableColor("#00FF41"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .typewriter,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#00FF41")
    )
    
    // MARK: 8. Cinema
    
    /// Cinema — Gold-yellow text in a light-weight font at the bottom with a
    /// subtle shadow and no background. The timeless movie subtitle look.
    static let cinema = CaptionStyle(
        name: "Cinema",
        fontName: "System-Light",
        fontSize: 24,
        textColor: CodableColor("#FFD700"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#000000")
    )
    
    // MARK: 9. Fire
    
    /// Fire — Bold orange-red text with word-by-word yellow highlight on a dark
    /// semi-transparent background. High-energy style for hype content.
    static let fire = CaptionStyle(
        name: "Fire",
        fontName: "System-Bold",
        fontSize: 32,
        textColor: CodableColor("#FF4500"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#1A1A1A"),
        backgroundOpacity: 0.75,
        cornerRadius: 10,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 6,
        shadowColor: CodableColor("#FF4500")
    )
    
    // MARK: 10. Outline
    
    /// Outline — Bold white text with a strong black shadow that creates an
    /// outline / stroke effect. No background, center position. Readable on
    /// any footage.
    static let outline = CaptionStyle(
        name: "Outline",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .center,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 6,
        shadowColor: CodableColor("#000000")
    )
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
