@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// Parsing the `#RRGGBB` / `#AARRGGBB` strings every preset is written in.
final class HexChannelsTests: XCTestCase {
    private func channels(_ hex: String) -> [UInt8] {
        let parsed = HexChannels(hex: hex)
        return [parsed.alpha, parsed.red, parsed.green, parsed.blue]
    }

    private let white: [UInt8] = [255, 255, 255, 255]

    // MARK: - Valid

    func testSixDigitsAreOpaque() {
        XCTAssertEqual(channels("#FF8000"), [255, 255, 128, 0])
    }

    func testEightDigitsCarryAlphaFirst() {
        XCTAssertEqual(channels("#66FFFFFF"), [0x66, 255, 255, 255])
    }

    func testLowercaseDigitsParse() {
        XCTAssertEqual(channels("#7c3aed"), [255, 0x7C, 0x3A, 0xED])
    }

    func testTheHashIsOptional() {
        XCTAssertEqual(channels("7C3AED"), [255, 0x7C, 0x3A, 0xED])
    }

    func testSurroundingSpacesAreIgnored() {
        XCTAssertEqual(channels("  #7C3AED  "), [255, 0x7C, 0x3A, 0xED])
    }

    func testBlackAndFullyTransparentParse() {
        XCTAssertEqual(channels("#000000"), [255, 0, 0, 0])
        XCTAssertEqual(channels("#00000000"), [0, 0, 0, 0])
    }

    // MARK: - Invalid falls back to white

    func testTheWrongLengthIsWhite() {
        XCTAssertEqual(channels("#FFF"), white)
        XCTAssertEqual(channels("#12345"), white)
        XCTAssertEqual(channels("#1234567"), white)
        XCTAssertEqual(channels("#123456789"), white)
    }

    func testAnEmptyStringIsWhite() {
        XCTAssertEqual(channels(""), white)
        XCTAssertEqual(channels("#"), white)
    }

    /// Scanner stopped at the first bad digit and parsed this as black.
    func testANonHexDigitIsWhiteNotBlack() {
        XCTAssertEqual(channels("#GG0000"), white)
        XCTAssertEqual(channels("#00GG00"), white)
    }

    func testASignIsNotADigit() {
        XCTAssertEqual(channels("#+12345"), white)
        XCTAssertEqual(channels("#-12345"), white)
    }

    func testTwoHashesAreInvalid() {
        XCTAssertEqual(channels("##7C3AED"), white)
    }

    // MARK: - Every preset

    /// A preset colour that fails to parse draws white, silently.
    func testEveryPresetColourIsValidHex() {
        for style in CaptionStyle.presets {
            for (role, hex) in [
                ("text", style.textColor.hex),
                ("highlight", style.highlightColor.hex),
                ("background", style.backgroundColor.hex),
            ] {
                let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
                XCTAssertTrue(
                    [6, 8].contains(digits.count) && digits.allSatisfy(\.isHexDigit),
                    "\(style.name) \(role) colour \(hex) is not valid hex"
                )
            }
        }
    }

    // MARK: - Color(hex:)

    func testColorFromHexHasThoseChannels() {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(Color(hex: "#80FF8000")).getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        XCTAssertEqual(red, 1, accuracy: 0.001)
        XCTAssertEqual(green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001)
        XCTAssertEqual(alpha, 128.0 / 255, accuracy: 0.001)
    }
}
