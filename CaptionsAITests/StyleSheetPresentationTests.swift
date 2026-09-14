@testable import CaptionsAI
import SwiftUI
import XCTest

/// The sheet the style scroller lives in.
///
/// Two separate ways the taller chip could be made unusable: a fixed detent
/// that cannot be grown, and the system text size inflating the sample until it
/// no longer fits the plate.
@MainActor
final class StyleSheetPresentationTests: XCTestCase {
    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    private func size(_ style: CaptionStyle, _ typeSize: DynamicTypeSize) throws -> CGSize {
        let renderer = ImageRenderer(
            content: StylePreviewCard(style: style, isSelected: false, previewText: "Check out this caption on video")
                .environment(\.dynamicTypeSize, typeSize)
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "the chip did not render").size
    }

    // MARK: - The sheet can be grown

    /// `[.height(300)]` alone is a hard cap: at the largest accessibility text
    /// sizes the Text Size slider is pushed below the fold and there is no
    /// gesture that can reach it, because a single detent cannot be dragged.
    func testTheSheetCanBeGrownToFullHeight() {
        XCTAssertTrue(StyleSheetView.detents.contains(.large), "the sheet cannot be dragged open")
    }

    func testTheRestingHeightHasRoomForTheChipRowAndTheSlider() {
        XCTAssertTrue(StyleSheetView.detents.contains(.height(StyleSheetView.restingHeight)))
        XCTAssertGreaterThanOrEqual(
            StyleSheetView.restingHeight,
            StylePreviewCard.plateHeight + 200,
            "the chip row and the size slider do not both fit"
        )
    }

    // MARK: - The chip is immune to the system text size

    /// Measured with the clamp removed: the card grows from 124pt to 158pt at
    /// accessibility5, for every preset. The style-name label under the plate
    /// is the bulk of it, and inside the plate there is a second effect —
    /// `Font.custom(_:size:)` scales with the text size and
    /// `Font.system(size:)` does not, so the six presets that name a real
    /// typeface would diverge from the other fourteen.
    ///
    /// The chip is a swatch: it has to stay the height of the row it scrolls
    /// in. The captions themselves are drawn by the renderer and are
    /// unaffected; the Text Size slider is how caption size is changed.
    func testANamedTypefaceChipDoesNotGrowWithTheSystemTextSize() throws {
        let ticker = try preset("Ticker")

        XCTAssertEqual(
            try size(ticker, .large).height,
            try size(ticker, .accessibility5).height,
            accuracy: 0.5,
            "the chip grew with the system text size and no longer matches the row"
        )
    }

    func testASystemFontChipIsAlsoUnaffected() throws {
        let hormozi = try preset("Hormozi")

        XCTAssertEqual(
            try size(hormozi, .large).height,
            try size(hormozi, .accessibility5).height,
            accuracy: 0.5
        )
    }
}
