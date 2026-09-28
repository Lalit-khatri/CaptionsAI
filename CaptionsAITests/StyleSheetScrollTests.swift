@testable import CaptionsAI
import XCTest

final class StyleSheetScrollTests: XCTestCase {
    func testOpeningOnAllTargetsTheSelectedStyle() {
        XCTAssertEqual(StyleSheetView.scrollTarget(selected: "Nordic Mint", among: CaptionStyle.presets), "Nordic Mint")
    }

    func testTheFirstStyleSelectedIsItsOwnTarget() {
        XCTAssertEqual(StyleSheetView.scrollTarget(selected: "Hormozi", among: CaptionStyle.presets), "Hormozi")
    }

    func testATabHoldingTheSelectionTargetsIt() {
        XCTAssertEqual(StyleSheetView.scrollTarget(selected: "Comic Hero", among: StyleCategory.styles(in: .fun)), "Comic Hero")
    }

    func testATabWithoutTheSelectionTargetsItsFirstStyle() {
        // Fun in preset order: Vox Box (boldBox) comes before Candy.
        XCTAssertEqual(StyleSheetView.scrollTarget(selected: "Hormozi", among: StyleCategory.styles(in: .fun)), "Vox Box")
    }

    func testAStyleThatIsNotAPresetTargetsTheFirstChip() {
        XCTAssertEqual(StyleSheetView.scrollTarget(selected: "My Own Style", among: CaptionStyle.presets), "Hormozi")
    }

    func testAnEmptyListHasNothingToScrollTo() {
        XCTAssertNil(StyleSheetView.scrollTarget(selected: "Hormozi", among: []))
    }
}
