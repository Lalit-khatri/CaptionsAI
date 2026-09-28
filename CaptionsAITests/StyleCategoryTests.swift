@testable import CaptionsAI
import XCTest

final class StyleCategoryTests: XCTestCase {
    // MARK: - Every preset has exactly one home

    func testEveryPresetBelongsToACategory() {
        let uncategorised = CaptionStyle.presets.filter { StyleCategory.of($0) == nil }.map(\.name)
        XCTAssertEqual(uncategorised, [])
    }

    func testNoPresetIsListedInTwoCategories() {
        let listed = StyleCategory.allCases.flatMap { StyleCategory.members[$0, default: []] }
        XCTAssertEqual(listed.count, Set(listed).count)
    }

    func testEveryListedNameIsARealPreset() {
        // A typo here would silently drop a style out of its tab.
        let presetNames = Set(CaptionStyle.presets.map(\.name))
        let listed = StyleCategory.allCases.flatMap { StyleCategory.members[$0, default: []] }
        XCTAssertEqual(listed.filter { !presetNames.contains($0) }, [])
    }

    func testTheTabsTogetherShowEveryPresetOnce() {
        let total = StyleCategory.allCases.map { StyleCategory.styles(in: $0).count }.reduce(0, +)
        XCTAssertEqual(total, CaptionStyle.presets.count)
    }

    // MARK: - The agreed grouping

    func testTabsAreInTheAgreedOrderWithTheirTitles() {
        XCTAssertEqual(StyleCategory.allCases.map(\.title), ["Bold", "Clean", "Karaoke", "Fun"])
    }

    func testBoldHoldsTheHeavyAllCapsStyles() {
        XCTAssertEqual(
            Set(StyleCategory.styles(in: .bold).map(\.name)),
            ["Hormozi", "Beast", "Fire", "Outline", "Ticker", "Punch", "Focus", "Power Gym", "Iman Luxe"]
        )
    }

    func testCleanHoldsTheCalmStyles() {
        XCTAssertEqual(
            Set(StyleCategory.styles(in: .clean).map(\.name)),
            ["Ali Abdaal", "Cinema", "Editorial", "Frosted", "Shamani", "Dan Slate", "Side Note", "Nordic Mint"]
        )
    }

    func testKaraokeHoldsTheHighlightLedStyles() {
        XCTAssertEqual(
            Set(StyleCategory.styles(in: .karaoke).map(\.name)),
            ["Karaoke", "Cyber Glow", "CapCut Pop", "Auto Pill", "Submagic", "Blink Box"]
        )
    }

    func testFunHoldsThePlayfulStyles() {
        XCTAssertEqual(
            Set(StyleCategory.styles(in: .fun).map(\.name)),
            ["Candy", "Sticker", "Bubble", "Comic Hero", "Marker", "Terminal", "Vox Box"]
        )
    }

    // MARK: - Filtering

    func testAllIsEveryPresetInPresetOrder() {
        XCTAssertEqual(StyleCategory.styles(in: nil).map(\.name), CaptionStyle.presets.map(\.name))
    }

    func testATabKeepsPresetOrder() {
        // Hormozi is first in the presets and Iman Luxe late, whatever order
        // the category lists them in.
        let bold = StyleCategory.styles(in: .bold).map(\.name)
        XCTAssertEqual(bold.first, "Hormozi")
        XCTAssertEqual(bold.last, "Iman Luxe")
    }

    func testAStyleWithAnUnlistedNameIsInNoTabButStillInAll() {
        var custom = CaptionStyle.hormozi
        custom.name = "My Custom Style"
        let presets = [CaptionStyle.hormozi, custom]

        XCTAssertNil(StyleCategory.of(custom))
        XCTAssertEqual(StyleCategory.styles(in: .bold, from: presets).map(\.name), ["Hormozi"])
        XCTAssertEqual(StyleCategory.styles(in: nil, from: presets).map(\.name), ["Hormozi", "My Custom Style"])
    }

    func testTheCategoryOfAPresetIsFoundByName() {
        XCTAssertEqual(StyleCategory.of(.hormozi), .bold)
        XCTAssertEqual(StyleCategory.of(.cinema), .clean)
        XCTAssertEqual(StyleCategory.of(.karaoke), .karaoke)
        XCTAssertEqual(StyleCategory.of(.candy), .fun)
        XCTAssertEqual(StyleCategory.of(.boldBox), .fun) // shown as "Vox Box"
    }
}
