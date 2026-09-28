@testable import CaptionsAI
import SwiftUI
import XCTest

final class StyleSheetScrollTests: XCTestCase {
    func testOpeningOnAllCentresTheSelectedStyle() {
        XCTAssertEqual(
            StyleSheetView.scrollTarget(selected: "Nordic Mint", among: CaptionStyle.presets),
            StyleSheetView.ScrollTarget(name: "Nordic Mint", anchor: .center)
        )
    }

    func testTheFirstStyleSelectedIsStillCentredNotLeading() {
        XCTAssertEqual(
            StyleSheetView.scrollTarget(selected: "Hormozi", among: CaptionStyle.presets),
            StyleSheetView.ScrollTarget(name: "Hormozi", anchor: .center)
        )
    }

    func testATabHoldingTheSelectionCentresIt() {
        XCTAssertEqual(
            StyleSheetView.scrollTarget(selected: "Comic Hero", among: StyleCategory.styles(in: .fun)),
            StyleSheetView.ScrollTarget(name: "Comic Hero", anchor: .center)
        )
    }

    func testATabWithoutTheSelectionStartsAtItsFirstStyle() {
        // Fun in preset order: Vox Box (boldBox) comes before Candy.
        XCTAssertEqual(
            StyleSheetView.scrollTarget(selected: "Hormozi", among: StyleCategory.styles(in: .fun)),
            StyleSheetView.ScrollTarget(name: "Vox Box", anchor: .leading)
        )
    }

    func testAStyleThatIsNotAPresetStartsAtTheFirstChip() {
        XCTAssertEqual(
            StyleSheetView.scrollTarget(selected: "My Own Style", among: CaptionStyle.presets),
            StyleSheetView.ScrollTarget(name: "Hormozi", anchor: .leading)
        )
    }

    func testAnEmptyListHasNothingToScrollTo() {
        XCTAssertNil(StyleSheetView.scrollTarget(selected: "Hormozi", among: []))
    }
}
