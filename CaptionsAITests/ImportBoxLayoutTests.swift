@testable import CaptionsAI
import XCTest

final class ImportBoxLayoutTests: XCTestCase {
    func testAnEmptyLibraryGetsTheWelcomeBox() {
        XCTAssertEqual(ImportView.ImportBoxLayout(hasProjects: false), .hero)
    }

    func testALibraryWithProjectsFoldsTheBoxIntoARow() {
        XCTAssertEqual(ImportView.ImportBoxLayout(hasProjects: true), .compact)
    }

    func testWithProjectsTheBoxStretchesAndLeavesAnEightPointGap() {
        XCTAssertTrue(ImportView.ImportBoxLayout.compact.fills)
        XCTAssertEqual(ImportView.ImportBoxLayout.compact.bottomGap, 8)
    }

    func testTheWelcomeBoxDoesNotStretch() {
        XCTAssertFalse(ImportView.ImportBoxLayout.hero.fills)
    }

    func testOnAShortScreenTheBoxStopsAtOneRow() {
        XCTAssertEqual(ImportView.ImportBoxLayout.minimumFillHeight, 64)
    }

    func testTheWelcomeBoxIsSmallerThanItWas() {
        // It was 48pt of padding above and below a 48pt glyph.
        XCTAssertLessThan(ImportView.ImportBoxLayout.hero.verticalPadding, 48)
        XCTAssertLessThan(ImportView.ImportBoxLayout.hero.iconSize, 48)
    }
}
