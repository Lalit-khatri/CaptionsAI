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
    var isUppercase: Bool = false
    
    // MARK: - SwiftUI Helpers
    
    var font: Font {
        if fontName.contains("Rounded") {
            return .system(size: fontSize, weight: .heavy, design: .rounded)
        } else if fontName.contains("Heavy") || fontName.contains("Black") {
            return .system(size: fontSize, weight: .heavy)
        } else if fontName.contains("Bold") {
            return .system(size: fontSize, weight: .bold)
        } else if fontName.contains("Light") {
            return .system(size: fontSize, weight: .light)
        } else if fontName.contains("Medium") {
            return .system(size: fontSize, weight: .medium)
        } else if fontName == "Menlo" {
            return .custom("Menlo-Bold", size: fontSize)
        } else if UIFont(name: fontName, size: fontSize) != nil {
            return .custom(fontName, size: fontSize)
        } else {
            return .system(size: fontSize, weight: .bold)
        }
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
    /// Top 10 viral caption style presets (each defined in its own file in Models/Styles/)
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
        outline
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
