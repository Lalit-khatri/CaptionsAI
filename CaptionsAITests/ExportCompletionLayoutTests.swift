@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// What the export-completion screen measures.
///
/// Every number here was first recorded against the screen as it shipped, so
/// each assertion below states a change rather than a hope. The previous
/// commit's measurements, for the record:
///
/// - summary card drew **301pt of the 345pt** it was given, and 278pt when the
///   style name was shorter — a card whose width was a function of its text
/// - "Done" was **38pt** tall against Apple's 44pt minimum touch target
/// - the footer was **281pt** at the largest accessibility text size, on an
///   iPhone SE content area of 603pt
/// - the hero was 210pt tall on every phone
///
/// The measurements go through the same static label builders and the same
/// view types the screen itself draws, so a change to the screen moves these
/// numbers. `ExportView` as a whole cannot be rendered in a test: it needs a
/// `Project`, an `ExportViewModel` with a finished export, and a StoreKit
/// environment object.
@MainActor
final class ExportCompletionLayoutTests: XCTestCase {
    /// Content width on a 393pt-wide phone: the screen less `ExportView`'s
    /// 24pt horizontal padding on each side.
    private let contentWidth: CGFloat = 345

    private func height(_ view: some View, width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "nothing rendered").size.height
    }

    /// The width of the pixels actually drawn inside the frame it was given.
    /// A view that fills its width draws to both edges; one that hugs its
    /// content draws a narrower band in the middle.
    private func drawnWidth(_ view: some View, width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "nothing rendered")
        let bounds = try XCTUnwrap(CaptionInk.bounds(of: image), "the view drew no pixels")
        return bounds.width
    }

    private func summary(style: String = "Hormozi") -> ExportSummaryRow {
        ExportSummaryRow(format: "Reel", duration: "0:15", style: style)
    }

    // MARK: - The hero

    /// The owner's actual complaint was about a big phone: a 210pt thumbnail
    /// on a 926pt screen leaves the content floating in the middle. The hero
    /// now takes a share of the viewport, with a floor so it survives an
    /// iPhone SE and a ceiling so it does not become the whole screen.
    func testTheHeroGrowsWithTheScreen() {
        let se = ExportCompletionLayout.heroHeight(forViewportHeight: 603)
        let proMax = ExportCompletionLayout.heroHeight(forViewportHeight: 926)

        XCTAssertEqual(se, 265.32, accuracy: 0.5, "the hero no longer tracks the viewport")
        XCTAssertGreaterThan(proMax, se, "the hero is the same size on a Pro Max as on an SE")
    }

    /// Both ends of the clamp, stated separately so a regression in one does
    /// not hide behind the other.
    func testTheHeroStopsGrowingAndStopsShrinking() {
        XCTAssertEqual(ExportCompletionLayout.heroHeight(forViewportHeight: 2000), 340, accuracy: 0.001, "no ceiling")
        XCTAssertEqual(ExportCompletionLayout.heroHeight(forViewportHeight: 400), 200, accuracy: 0.001, "no floor")
        XCTAssertEqual(ExportCompletionLayout.heroHeight(forViewportHeight: 0), 200, accuracy: 0.001, "an unmeasured container must not collapse the hero")
    }

    func testTheHeroIsAPortraitCard() {
        XCTAssertEqual(ExportCompletionLayout.heroAspectRatio, 140.0 / 210.0, accuracy: 0.0001)
        XCTAssertLessThan(ExportCompletionLayout.heroAspectRatio, 1, "the hero is meant to be taller than it is wide")
    }

    // MARK: - The summary card

    /// Was 301pt of 345. The columns bunched in the middle of a grey box
    /// narrower than everything above and below it — the owner's "compacted in
    /// the centre", reproduced inside a single element.
    func testTheSummaryCardFillsTheWidthItIsGiven() throws {
        let drawn = try drawnWidth(summary(), width: contentWidth)
        print("summary card drawn width: \(drawn)pt of \(contentWidth)pt")

        XCTAssertEqual(drawn, contentWidth, accuracy: 1, "the card still hugs its content")
    }

    /// The corollary: the card must be one size, not a size per project.
    func testTheCardIsTheSameWidthWhateverIsInIt() throws {
        let short = try drawnWidth(summary(style: "Bold"), width: contentWidth)
        let long = try drawnWidth(summary(style: "Editorial"), width: contentWidth)
        print("summary card: short=\(short)pt long=\(long)pt")

        XCTAssertEqual(short, long, accuracy: 0.5, "the card width still tracks its content")
    }

    // MARK: - The footer

    /// Was 38pt — the only control on the screen under the 44pt minimum.
    func testTheDoneButtonMeetsTheMinimumTouchTarget() throws {
        let h = try height(ExportCompletionFooter.doneLabel(), width: contentWidth)
        print("Done button height: \(h)pt")

        XCTAssertGreaterThanOrEqual(h, 44, "Done is still under the 44pt touch minimum")
    }

    /// "Share Video" wrapped to three lines at the largest accessibility text
    /// size and measured 166pt. Holding it to one line brings it to 103pt.
    ///
    /// It does not come down further, and the bound below says 120 rather
    /// than something tighter for a reason: most of what is left is the SF
    /// Symbol, which scales with Dynamic Type and is not affected by
    /// `minimumScaleFactor` — that modifier scales text. Shrinking it would
    /// mean capping the button's Dynamic Type, which trades a real
    /// accessibility need for a number, on the screen's primary action. The
    /// footer is pinned by `safeAreaInset`, so its height costs scrolling
    /// room and never reachability.
    func testTheShareButtonDoesNotWrapAtTheLargestTextSize() throws {
        let label = ExportCompletionFooter.shareLabel()
            .environment(\.dynamicTypeSize, .accessibility5)
        let h = try height(label, width: contentWidth)
        print("Share button height at accessibility5: \(h)pt")

        XCTAssertLessThan(h, 120, "Share still wraps at AX5")
    }

    /// Was 281pt of an iPhone SE's 603pt content area; now 226pt, which
    /// leaves 377pt of scrolling room. The remainder is Dynamic Type doing
    /// what it is supposed to do — see the share-button test above.
    func testTheFooterStaysReasonableAtTheLargestTextSize() throws {
        let footer = ExportCompletionFooter(onShare: {}, onDone: {})
            .environment(\.dynamicTypeSize, .accessibility5)
        let h = try height(footer, width: contentWidth)
        print("footer height at accessibility5: \(h)pt")

        XCTAssertLessThan(h, 240, "the footer still takes half the screen at AX5")
    }

    /// And the default size must not have been sacrificed to fix AX5.
    func testTheFooterIsModestAtTheDefaultTextSize() throws {
        let h = try height(ExportCompletionFooter(onShare: {}, onDone: {}), width: contentWidth)
        print("footer height at default type: \(h)pt")

        XCTAssertLessThan(h, 170)
        XCTAssertGreaterThan(h, 80)
    }
}
