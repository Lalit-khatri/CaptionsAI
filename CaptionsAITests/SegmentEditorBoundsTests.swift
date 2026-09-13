@testable import CaptionsAI
import XCTest

/// Whether the caption timing editor can be opened at all on a long video.
///
/// The defect: the End stepper was declared `in: startTime ... 3600`. A
/// `ClosedRange` with `upperBound < lowerBound` is not a range — forming one
/// traps — so on any video longer than an hour, tapping a caption that starts
/// after 60:00 crashed the app outright. The same literal was wrong the other
/// way for everything else: in a 90-second video it offered to stretch a
/// caption to an hour, well past the last frame.
///
/// A trap cannot be asserted from a test without taking the whole bundle down
/// with it, so these assert the bound the range is built from. Two properties
/// make the crash impossible and the stepper honest: the upper bound is never
/// below the lower bound, and it is the video's own length.
final class SegmentEditorBoundsTests: XCTestCase {
    private func latestEnd(start: Double, end: Double, duration: Double) -> Double {
        SegmentEditorSheet.latestEnd(start: start, end: end, videoDuration: duration)
    }

    // MARK: - The crash

    func testACaptionPastTheOneHourMarkStillHasARange() {
        // 66:40 into a two-hour video.
        let start = 4000.0
        let bound = latestEnd(start: start, end: 4005, duration: 7200)

        XCTAssertGreaterThanOrEqual(bound, start, "startTime ... \(bound) is not a range; this traps")
    }

    func testNoSegmentOfAnyVideoProducesAnEmptyRange() {
        let durations = [0.0, 12.5, 90, 3599, 3600, 3601, 7200, 36000]

        for duration in durations {
            for start in [0.0, duration / 2, max(0, duration - 1), duration] {
                let end = min(start + 2, max(start, duration))
                let bound = latestEnd(start: start, end: end, duration: duration)
                XCTAssertGreaterThanOrEqual(
                    bound, start,
                    "duration \(duration), start \(start): upper bound \(bound) is below the lower bound"
                )
            }
        }
    }

    // MARK: - The bound is the video

    func testACaptionCanBeStretchedToTheEndOfTheVideo() {
        XCTAssertEqual(latestEnd(start: 5, end: 6, duration: 90), 90)
    }

    func testAShortVideoDoesNotOfferAnHour() {
        XCTAssertEqual(latestEnd(start: 5, end: 6, duration: 90), 90)
        XCTAssertNotEqual(latestEnd(start: 5, end: 6, duration: 90), 3600)
    }

    func testALongVideoOffersItsWholeLength() {
        XCTAssertEqual(latestEnd(start: 4000, end: 4005, duration: 7200), 7200)
    }

    // MARK: - The value on screen stays reachable

    func testACaptionEndingPastTheVideoKeepsItsCurrentValueInRange() {
        // A duration of 0 is what a project has before its video is measured.
        let bound = latestEnd(start: 20, end: 30, duration: 0)

        XCTAssertGreaterThanOrEqual(bound, 30)
    }
}
