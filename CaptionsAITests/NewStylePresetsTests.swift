@testable import CaptionsAI
import UIKit
import XCTest

/// The ten presets added on top of the original ten, and the properties a
/// preset has to satisfy to be shippable at all.
///
/// A caption preset is unusually easy to get wrong in a way nothing notices:
/// name a typeface the device does not have and it silently falls back to the
/// system font, so the preset still renders, still passes any test that only
/// checks it exists, and simply is not the style it claims to be. Every
/// assertion here exists because some way of being wrong is invisible.
@MainActor
final class NewStylePresetsTests: XCTestCase {
    /// The full line-up, in order. The original ten first — their order is
    /// load-bearing, because `Project.selectedStyle` falls back to
    /// `presets.first` for any name it cannot resolve.
    private static let expectedNames = [
        "Hormozi", "Beast", "Submagic", "Ali Abdaal", "Cyber Glow",
        "Karaoke", "Cinema", "Fire", "Vox Box", "Outline",
        "Ticker", "Candy", "Sticker", "Punch", "Terminal",
        "Editorial", "Focus", "Frosted", "Bubble", "Marker",
        "Shamani",
    ]

    private static let newNames = Array(expectedNames.dropFirst(10))

    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(
            CaptionStyle.presets.first { $0.name == name },
            "no preset named \(name)"
        )
    }

    // MARK: - They exist, in order

    func testThereAreTwentyOnePresets() {
        XCTAssertEqual(CaptionStyle.presets.count, 21)
    }

    func testThePresetsAreTheOnesWeMeant() {
        XCTAssertEqual(CaptionStyle.presets.map(\.name), Self.expectedNames)
    }

    /// The first preset is the fallback for every project whose stored style
    /// name no longer resolves, and it is also the literal default in
    /// `Project.init`. Ten new presets must not displace it.
    func testTheFallbackPresetIsStillHormoziAndProjectAgrees() {
        XCTAssertEqual(CaptionStyle.presets.first?.name, "Hormozi")
        XCTAssertEqual(
            Project(videoURL: URL(fileURLWithPath: "/tmp/x.mov")).selectedStyleName,
            "Hormozi"
        )
    }

    // MARK: - Every named typeface is really on the device

    /// The defect this guards: `uiFontScaled(to:)` asks `UIFont(name:)` first
    /// and quietly drops to a system weight when the name is unknown. A typo
    /// in a font name is therefore invisible — the preset renders, in the
    /// wrong face, forever.
    ///
    /// Deliberately not written as "skip the ones that do not resolve", which
    /// is what the older typeface test does and which makes this whole class
    /// of mistake unobservable.
    func testEveryPresetThatNamesATypefaceGetsThatTypeface() {
        let pseudo = ["System-Heavy", "System-Bold", "System-Medium", "System-Light", "System-Rounded"]

        for style in CaptionStyle.presets where !pseudo.contains(style.fontName) {
            XCTAssertNotNil(
                UIFont(name: style.fontName, size: style.fontSize),
                "\(style.name) names \(style.fontName), which is not installed — it will draw in the system font"
            )
        }
    }

    /// "Menlo" is special-cased into Menlo-Bold for the preview but exports as
    /// Menlo-Regular, so the bare family name must never appear in a preset.
    func testNoPresetUsesTheBareMenloName() {
        XCTAssertFalse(CaptionStyle.presets.contains { $0.fontName == "Menlo" })
    }

    // MARK: - Every preset is within the sizes the app allows

    /// The Text Size slider runs 16…48 and overwrites the preset's own size,
    /// so a preset outside that range cannot be restored once a user touches
    /// the slider.
    func testEveryPresetSizeIsReachableWithTheSlider() {
        for style in CaptionStyle.presets {
            XCTAssertTrue(
                (16...48).contains(style.fontSize),
                "\(style.name) is \(style.fontSize)pt, outside the 16…48 the slider offers"
            )
        }
    }

    // MARK: - Twenty presets, not ten presets twice

    /// Identity is the name, so two presets can look identical and still both
    /// appear in the picker. This compares what a user actually sees.
    func testNoTwoPresetsLookTheSame() {
        struct Look: Hashable {
            let font: String
            let size: CGFloat
            let text: String
            let highlight: String
            let background: String
            let opacity: CGFloat
            let radius: CGFloat
            let stroke: CGFloat
            let position: TextPosition
            let uppercase: Bool
        }

        var seen: [Look: String] = [:]
        for style in CaptionStyle.presets {
            let look = Look(
                font: style.fontName,
                size: style.fontSize,
                text: style.textColor.hex,
                highlight: style.highlightColor.hex,
                background: style.backgroundColor.hex,
                opacity: style.backgroundOpacity,
                radius: style.cornerRadius,
                stroke: style.strokeWidth,
                position: style.position,
                uppercase: style.isUppercase
            )
            if let twin = seen[look] {
                XCTFail("\(style.name) is indistinguishable from \(twin)")
            }
            seen[look] = style.name
        }
    }

    // MARK: - Every preset actually draws something

    /// A preset can be well-formed and still render nothing — an opacity, a
    /// colour or a position can put the ink where no one sees it. This is the
    /// only check that runs all twenty through the export renderer.
    func testEveryPresetPutsInkOnTheFrame() throws {
        let segment = CaptionInk.segment(text: "VIRAL CAPTIONS", words: true)
        let size = CGSize(width: 1080, height: 1920)

        for style in CaptionStyle.presets {
            let bounds = CaptionInk.exportBounds(style: style, segment: segment, in: size)
            let width = try XCTUnwrap(bounds, "\(style.name) rendered nothing at all").width
            XCTAssertGreaterThan(width, 0, "\(style.name) drew no ink")
        }
    }

    // MARK: - The new ten, individually

    func testTickerIsCondensed() throws {
        let ticker = try preset("Ticker")
        XCTAssertEqual(ticker.fontName, "AvenirNextCondensed-Heavy")
        XCTAssertEqual(ticker.uiFont.familyName, "Avenir Next Condensed")
        XCTAssertTrue(ticker.isUppercase)
    }

    func testCandyIsAFullyOpaquePill() throws {
        let candy = try preset("Candy")
        XCTAssertEqual(candy.backgroundOpacity, 1.0)
        XCTAssertGreaterThanOrEqual(candy.cornerRadius, 24, "a pill, not a box")
        XCTAssertEqual(candy.backgroundColor.hex, "#FF2E9F")
    }

    /// Every other preset is light text on dark video. This one is the
    /// inversion, and the shadow has to be off: a black blur under near-black
    /// glyphs on a white chip is a smear.
    func testStickerIsDarkTextOnALightChip() throws {
        let sticker = try preset("Sticker")
        XCTAssertEqual(sticker.backgroundColor.hex, "#FFFFFF")
        XCTAssertEqual(sticker.backgroundOpacity, 1.0)
        XCTAssertEqual(sticker.textColor.hex, "#0B0B0F")
        XCTAssertEqual(sticker.shadowRadius, 0)
    }

    func testPunchIsOutlinedAndHasNoBoxOrBlurToHideBehind() throws {
        let punch = try preset("Punch")
        XCTAssertGreaterThan(punch.strokeWidth, 0)
        XCTAssertEqual(punch.backgroundOpacity, 0)
        XCTAssertEqual(punch.shadowRadius, 0)
    }

    func testTerminalIsMonospacedAndLowercase() throws {
        let terminal = try preset("Terminal")
        XCTAssertEqual(terminal.fontName, "Menlo-Bold")
        XCTAssertTrue(terminal.uiFont.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        XCTAssertFalse(terminal.isUppercase, "the lowercase is the whole look")
    }

    func testEditorialIsASerif() throws {
        let editorial = try preset("Editorial")
        XCTAssertEqual(editorial.uiFont.familyName, "Georgia")
        XCTAssertFalse(editorial.isUppercase)
    }

    /// The only preset that uses a translucent text colour: inactive words are
    /// 40% white and the active one is opaque, so the eye is pulled along the
    /// line rather than to a colour change.
    func testFocusDimsTheWordsItIsNotOn() throws {
        let focus = try preset("Focus")
        XCTAssertEqual(focus.textColor.hex.count, 9, "expected 8-digit AARRGGBB")
        XCTAssertEqual(focus.textColor.hex, "#66FFFFFF")
        XCTAssertEqual(focus.highlightColor.hex, "#FFFFFFFF")
        XCTAssertTrue(focus.wordByWordHighlight)
    }

    func testFrostedIsALightChipNotADarkOne() throws {
        let frosted = try preset("Frosted")
        XCTAssertEqual(frosted.backgroundColor.hex, "#FFFFFF")
        XCTAssertGreaterThan(frosted.backgroundOpacity, 0)
        XCTAssertLessThan(frosted.backgroundOpacity, 0.3, "translucent, or it is just Sticker")
    }

    func testBubbleIsRoundedAndOutlined() throws {
        let bubble = try preset("Bubble")
        XCTAssertEqual(bubble.fontName, "System-Rounded")
        XCTAssertGreaterThan(bubble.strokeWidth, 0)
        XCTAssertEqual(bubble.backgroundOpacity, 0)
    }

    func testMarkerIsAHandTypeface() throws {
        let marker = try preset("Marker")
        XCTAssertEqual(marker.fontName, "Noteworthy-Bold")
        XCTAssertEqual(marker.uiFont.familyName, "Noteworthy")
        XCTAssertFalse(marker.isUppercase)
    }

    func testShamaniIsCompactVerticalStackWithPopScale() throws {
        let shamani = try preset("Shamani")
        XCTAssertEqual(shamani.maxWidthFraction, 0.55, "constrained width forces compact vertical stack")
        XCTAssertEqual(shamani.wordHighlightEffect, .popScale)
        XCTAssertEqual(shamani.animation, .bounce)
        XCTAssertEqual(shamani.highlightColor.hex, "#FFE600")
    }

    // MARK: - The new ten as a group

    /// Ten more of the same is not ten more styles. Between them the new
    /// presets have to cover the axes the original ten left empty.
    func testTheNewPresetsAreNotAllTheSameShape() throws {
        let new = try Self.newNames.map { try preset($0) }

        XCTAssertGreaterThanOrEqual(Set(new.map(\.fontName)).count, 7, "too few distinct typefaces")
        XCTAssertTrue(new.contains { $0.isUppercase }, "none are uppercase")
        XCTAssertTrue(new.contains { !$0.isUppercase }, "all are uppercase")
        XCTAssertTrue(new.contains { $0.backgroundOpacity > 0 }, "none have a box")
        XCTAssertTrue(new.contains { $0.backgroundOpacity == 0 }, "all have a box")
        XCTAssertTrue(new.contains { $0.strokeWidth > 0 }, "none outline")
        XCTAssertGreaterThanOrEqual(Set(new.map(\.position)).count, 2, "all sit in the same place")
    }
}
