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
        clean, bold, neon, minimal, highlight, typewriter, subtitle, pop
    ]
    
    /// Clean — White SF Pro with subtle shadow (like Apple Live Captions)
    static let clean = CaptionStyle(
        name: "Clean",
        fontName: "System",
        fontSize: 22,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 8,
        position: .bottomCenter,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000")
    )
    
    /// Bold — White text on black background box (classic YouTube)
    static let bold = CaptionStyle(
        name: "Bold",
        fontName: "System-Bold",
        fontSize: 24,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.8,
        cornerRadius: 8,
        position: .bottomCenter,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 0,
        shadowColor: CodableColor("#000000")
    )
    
    /// Neon — Rounded font with colored glow on dark bg (TikTok trending)
    static let neon = CaptionStyle(
        name: "Neon",
        fontName: "System-Bold",
        fontSize: 26,
        textColor: CodableColor("#00FFFF"),
        highlightColor: CodableColor("#FF00FF"),
        backgroundColor: CodableColor("#1A1A2E"),
        backgroundOpacity: 0.7,
        cornerRadius: 12,
        position: .center,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 12,
        shadowColor: CodableColor("#00FFFF")
    )
    
    /// Minimal — Thin font, bottom center, no background (professional/cinematic)
    static let minimal = CaptionStyle(
        name: "Minimal",
        fontName: "System-Light",
        fontSize: 20,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .fadeIn,
        wordByWordHighlight: false,
        shadowRadius: 2,
        shadowColor: CodableColor("#000000")
    )
    
    /// Highlight — Word-by-word highlight in yellow (Hormozi/podcast style)
    static let highlight = CaptionStyle(
        name: "Highlight",
        fontName: "System-Bold",
        fontSize: 28,
        textColor: CodableColor("#FFFFFF"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.5,
        cornerRadius: 8,
        position: .center,
        animation: .highlight,
        wordByWordHighlight: true,
        shadowRadius: 4,
        shadowColor: CodableColor("#000000")
    )
    
    /// Typewriter — Monospace, appear letter by letter (storytelling)
    static let typewriter = CaptionStyle(
        name: "Typewriter",
        fontName: "Menlo",
        fontSize: 20,
        textColor: CodableColor("#E0E0E0"),
        highlightColor: CodableColor("#FFFFFF"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .typewriter,
        wordByWordHighlight: false,
        shadowRadius: 2,
        shadowColor: CodableColor("#000000")
    )
    
    /// Subtitle — Yellow text at bottom, no background (classic movie subtitle)
    static let subtitle = CaptionStyle(
        name: "Subtitle",
        fontName: "System",
        fontSize: 22,
        textColor: CodableColor("#FFD700"),
        highlightColor: CodableColor("#FFD700"),
        backgroundColor: CodableColor("#000000"),
        backgroundOpacity: 0.0,
        cornerRadius: 0,
        position: .bottomCenter,
        animation: .none,
        wordByWordHighlight: false,
        shadowRadius: 3,
        shadowColor: CodableColor("#000000")
    )
    
    /// Pop — Bold, colorful, bounce animation (high energy content)
    static let pop = CaptionStyle(
        name: "Pop",
        fontName: "System-Bold",
        fontSize: 30,
        textColor: CodableColor("#FF6B6B"),
        highlightColor: CodableColor("#4ECDC4"),
        backgroundColor: CodableColor("#FFFFFF"),
        backgroundOpacity: 0.9,
        cornerRadius: 16,
        position: .center,
        animation: .bounce,
        wordByWordHighlight: true,
        shadowRadius: 0,
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
