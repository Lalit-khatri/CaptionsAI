@testable import CaptionsAI
import SwiftData
import XCTest

/// What happens when speech recognition hangs or takes too long.
///
/// Apple's `SFSpeechRecognitionTask` continuation only resumes when `isFinal`
/// is received or an explicit `recognitionError` is reported. If the recognizer
/// stalls — network drop, daemon hang, or audio stream silence that never
/// finishes — the continuation is never resumed.
///
/// Without a deadline, `generateCaptions()` sits awaiting the recognizer
/// indefinitely, leaving the user with an infinite processing spinner and
/// no explanation.
@MainActor
final class TranscriptionTimeoutTests: XCTestCase {

    private func makeProject(in context: ModelContext, duration: Double = 10) throws -> Project {
        let project = Project(
            name: "Test",
            videoURL: TestSupport.placeholderVideoURL,
            videoDuration: duration
        )
        context.insert(project)
        project.addSegment(CaptionSegment(startTime: 0, endTime: 1, text: "original captions"))
        try context.save()
        return project
    }

    // MARK: - View Model Tests

    func testTranscriptionThatHangsIndefinitelyTimesOutAndReportsError() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context)

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangIndefinitely

        // Inject a 50ms budget so the test finishes in a fraction of a second.
        let viewModel = EditorViewModel(
            project: project,
            speechRecognizer: transcriber,
            transcriptionBudget: 0.05
        )

        let task = Task { await viewModel.generateCaptions() }

        await waitUntil("transcription to start") { transcriber.recognizeCallCount == 1 }
        XCTAssertTrue(viewModel.isProcessing, "transcription did not start processing")

        // Wait for generateCaptions to complete via the deadline timeout
        await waitUntil("transcription to time out", timeout: 2.0) {
            !viewModel.isProcessing
        }
        task.cancel()
        _ = await task.result

        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(
            viewModel.error,
            SpeechError.timedOut.localizedDescription,
            "error message does not explain the timeout"
        )
        XCTAssertEqual(
            project.sortedSegments.map(\.text),
            ["original captions"],
            "timed-out transcription corrupted existing captions"
        )
    }

    func testFastTranscriptionCompletesImmediatelyWithoutWaitingForBudget() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context)

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .succeed([
            CaptionSegment(startTime: 0, endTime: 1, text: "fresh captions"),
        ])

        // Full 90-second budget: must NOT delay a fast result.
        let viewModel = EditorViewModel(
            project: project,
            speechRecognizer: transcriber,
            transcriptionBudget: 90
        )

        await viewModel.generateCaptions()

        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.segments.map(\.text), ["fresh captions"])
    }

    func testTranscriptionBudgetScalesWithClipDuration() {
        // Clips shorter than 15s are clamped to the 90s minimum.
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 0), 90)
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 5), 90)
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 10), 90)
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 15), 90)

        // Longer clips scale at 6x duration.
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 30), 180)
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 60), 360)
        XCTAssertEqual(EditorViewModel.transcriptionBudget(forClipOf: 300), 1800)
    }

    // MARK: - Deadline Helper Tests

    func testDeadlineHelperReturnsValueWhenCompletedBeforeDeadline() async throws {
        let result = try await withDeadline(
            seconds: 5.0,
            throwing: { SpeechError.timedOut }
        ) {
            42
        }
        XCTAssertEqual(result, 42)
    }

    func testDeadlineHelperThrowsWhenTimeExpires() async {
        struct MockTimeout: Error, Equatable {}

        do {
            _ = try await withDeadline(
                seconds: 0.01,
                throwing: { MockTimeout() },
                sleep: { _ in } // Instant sleep to trigger timeout immediately
            ) {
                // Operation that never returns
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            XCTFail("expected timeout error, but call succeeded")
        } catch let error as MockTimeout {
            XCTAssertEqual(error, MockTimeout())
        } catch {
            XCTFail("unexpected error thrown: \(error)")
        }
    }

    func testDeadlineHelperPropagatesCancellationImmediately() async {
        let task = Task {
            try await withDeadline(
                seconds: 60.0,
                throwing: { SpeechError.timedOut }
            ) {
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        // Give task a turn to start, then cancel it
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation, but task completed")
        } catch is CancellationError {
            // Success
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
