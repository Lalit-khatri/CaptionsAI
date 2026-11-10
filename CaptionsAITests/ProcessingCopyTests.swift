@testable import CaptionsAI
import XCTest

final class ProcessingCopyTests: XCTestCase {
    func testAnalysingIsUnchangedForApplesRecogniser() {
        XCTAssertEqual(ProcessingView.title(for: nil), "Analyzing Speech...")
        XCTAssertEqual(ProcessingView.status(progress: 0.42, preparation: nil), "Processing 42%")
    }

    func testTheDownloadShowsItsOwnProgressNotTheRecognisers() {
        XCTAssertEqual(ProcessingView.title(for: .downloading(fraction: 0.3)), "Downloading Speech Model...")
        XCTAssertEqual(ProcessingView.status(progress: 0, preparation: .downloading(fraction: 0.3)), "Downloading 30%")
    }

    func testLoadingTheModelSaysItIsOnlySlowOnce() {
        XCTAssertEqual(ProcessingView.title(for: .loading), "Preparing Speech Model...")
        XCTAssertEqual(ProcessingView.status(progress: 0, preparation: .loading), "Only slow the first time")
    }
}
