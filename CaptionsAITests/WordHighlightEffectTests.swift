@testable import CaptionsAI
import CoreGraphics
import SwiftUI
import XCTest

@MainActor
final class WordHighlightEffectTests: XCTestCase {
    func testAllHighlightEffectCasesHaveDisplayNames() {
        for effect in WordHighlightEffect.allCases {
            XCTAssertFalse(effect.displayName.isEmpty, "\(effect) has empty displayName")
        }
    }

    func testEffectCasesCount() {
        XCTAssertEqual(WordHighlightEffect.allCases.count, 5)
    }

    func testWithoutStrokePreservesAllOtherProperties() {
        let original = CaptionStyle.punch
        let stripped = original.withoutStroke

        XCTAssertEqual(stripped.strokeWidth, 0)
        XCTAssertEqual(stripped.name, original.name)
        XCTAssertEqual(stripped.fontName, original.fontName)
        XCTAssertEqual(stripped.fontSize, original.fontSize)
        XCTAssertEqual(stripped.textColor, original.textColor)
        XCTAssertEqual(stripped.highlightColor, original.highlightColor)
        XCTAssertEqual(stripped.maxWidthFraction, original.maxWidthFraction)
        XCTAssertEqual(stripped.horizontalOffsetFraction, original.horizontalOffsetFraction)
        XCTAssertEqual(stripped.wordHighlightEffect, original.wordHighlightEffect)
    }

    func testPillBoxPresetsHaveBlackContrastingText() {
        let pillPresets = CaptionStyle.presets.filter { $0.wordHighlightEffect == .pillBox }
        XCTAssertFalse(pillPresets.isEmpty, "at least one pill box preset must exist")

        for style in pillPresets {
            XCTAssertEqual(style.wordHighlightTextColor.hex, "#000000", "\(style.name) text must be black for contrast")
            XCTAssertFalse(style.wordHighlightBgColor.hex.isEmpty)
        }
    }

    func testOffsetPresetsSitAwayFromCenter() {
        let offsetPresets = CaptionStyle.presets.filter { $0.horizontalOffsetFraction != 0 }
        XCTAssertFalse(offsetPresets.isEmpty)

        for style in offsetPresets {
            XCTAssertTrue((-0.45...0.45).contains(style.horizontalOffsetFraction))
        }
    }

    func testConstrainedWidthPresetsAreUnderDefault() {
        let constrained = CaptionStyle.presets.filter { $0.maxWidthFraction < 0.85 }
        XCTAssertGreaterThanOrEqual(constrained.count, 5)

        for style in constrained {
            XCTAssertGreaterThanOrEqual(style.maxWidthFraction, 0.40)
        }
    }

    func testAllWordHighlightEffectsProduceExportInk() throws {
        let segment = CaptionInk.segment(text: "THE VIRAL FOCUS WORD", words: true)
        let size = CGSize(width: 1080, height: 1920)

        for effect in WordHighlightEffect.allCases {
            var style = CaptionStyle.hormozi
            style.wordByWordHighlight = true
            style.wordHighlightEffect = effect
            if effect == .pillBox {
                style.wordHighlightBgColor = CodableColor("#FFE600")
                style.wordHighlightTextColor = CodableColor("#000000")
            }

            let bounds = CaptionInk.exportBounds(style: style, segment: segment, in: size)
            let width = try XCTUnwrap(bounds, "effect \(effect) rendered no ink").width
            XCTAssertGreaterThan(width, 0, "effect \(effect) drew zero width")
        }
    }
}
