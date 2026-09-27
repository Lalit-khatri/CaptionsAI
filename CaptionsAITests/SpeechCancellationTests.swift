@testable import CaptionsAI
import Foundation
import XCTest

/// Cancelling transcription has to reach the work that is not a Swift task:
/// the asset reader copying audio out and the recogniser listening to it.
final class SpeechCancellationTests: XCTestCase {
    // MARK: - CancellationGate

    func testCancellingAfterAttachingRunsTheAction() {
        let gate = CancellationGate()
        var runs = 0
        gate.attach { runs += 1 }

        gate.cancel()

        XCTAssertEqual(runs, 1)
        XCTAssertTrue(gate.isCancelled)
    }

    /// Cancellation can arrive before the reader or recogniser exists. The
    /// action must still run, the moment it is attached.
    func testAttachingAfterCancellingRunsTheActionImmediately() {
        let gate = CancellationGate()
        gate.cancel()
        var runs = 0

        gate.attach { runs += 1 }

        XCTAssertEqual(runs, 1)
    }

    func testCancellingTwiceRunsTheActionOnce() {
        let gate = CancellationGate()
        var runs = 0
        gate.attach { runs += 1 }

        gate.cancel()
        gate.cancel()

        XCTAssertEqual(runs, 1)
    }

    func testNothingRunsWithoutCancellation() {
        let gate = CancellationGate()
        var runs = 0

        gate.attach { runs += 1 }

        XCTAssertEqual(runs, 0)
        XCTAssertFalse(gate.isCancelled)
    }

    func testCancellingWithNothingAttachedStillMarksTheGate() {
        let gate = CancellationGate()

        gate.cancel()

        XCTAssertTrue(gate.isCancelled)
    }

    func testOnlyTheLatestAttachedActionRuns() {
        let gate = CancellationGate()
        var ran: [String] = []
        gate.attach { ran.append("first") }
        gate.attach { ran.append("second") }

        gate.cancel()

        XCTAssertEqual(ran, ["second"])
    }

    /// Cancellation arrives on whatever thread cancelled the task, racing the
    /// attach on the thread doing the work. Whichever order they land in,
    /// the action runs exactly once.
    func testRacingCancelAndAttachRunTheActionExactlyOnce() {
        for _ in 0 ..< 200 {
            let gate = CancellationGate()
            let lock = NSLock()
            var runs = 0

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    gate.attach { lock.withLock { runs += 1 } }
                } else {
                    gate.cancel()
                }
            }

            XCTAssertEqual(runs, 1)
        }
    }

    // MARK: - Audio extraction

    private func temporaryWAVs() -> Set<String> {
        let directory = FileManager.default.temporaryDirectory.path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return Set(names.filter { $0.hasSuffix(".wav") })
    }

    /// A caller that has already been cancelled gets `CancellationError`, not
    /// "failed to extract audio" — which the editor would show as an error
    /// banner for the user having walked away. The clip here has no audio,
    /// so any attempt to read it would fail with `audioExtractionFailed`.
    func testACancelledCallerGetsCancellationAndNoFile() async throws {
        let videoURL = try await TestSupport.makeTestVideo(seconds: 1.0)
        defer { TestSupport.remove(videoURL) }
        let before = temporaryWAVs()

        let outcome = await Task { () -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let url = try await SpeechRecognizer.extractAudioTrack(from: videoURL)
                TestSupport.remove(url)
                return "returned a file"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "failed: \(error)"
            }
        }.value

        XCTAssertEqual(outcome, "cancelled")
        XCTAssertEqual(temporaryWAVs().subtracting(before), [])
    }
}
