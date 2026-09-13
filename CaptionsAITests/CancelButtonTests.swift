@testable import CaptionsAI
import SwiftData
import XCTest

/// The Cancel button on the processing overlay.
///
/// It used to be wired to `viewModel.isProcessing = false`, which hid the
/// spinner and nothing else — the recogniser kept running and applied its
/// result over whatever the user did next. The view model now owns the task,
/// so these drive `startTranscription()` / `cancelTranscription()`, which is
/// exactly what `EditorView` calls.
@MainActor
final class CancelButtonTests: XCTestCase {

    private func makeProject(in context: ModelContext, editedText: String) throws -> Project {
        let project = Project(
            name: "Test",
            videoURL: TestSupport.placeholderVideoURL
        )
        context.insert(project)
        project.addSegment(CaptionSegment(startTime: 0, endTime: 1, text: editedText))
        try context.save()
        return project
    }

    private func persistedCaptionTexts(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<CaptionSegment>()).map(\.text)
    }

    /// Tapping Cancel must stop the work, not just stop drawing it.
    func testCancelStopsTheRunningTranscription() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, editedText: "kept")

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        viewModel.startTranscription()
        await waitUntil("transcription to start") { transcriber.recognizeCallCount == 1 }

        viewModel.cancelTranscription()

        XCTAssertFalse(viewModel.isProcessing, "the overlay was still up after Cancel")
        await waitUntil("the recogniser to observe cancellation") { transcriber.sawCancellation }
        XCTAssertEqual(try persistedCaptionTexts(context), ["kept"])
    }

    /// Cancelling is something the user chose. It is not a failure, and it
    /// must not leave an error banner behind.
    func testCancelDoesNotSurfaceAnError() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, editedText: "kept")

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        viewModel.startTranscription()
        await waitUntil("transcription to start") { transcriber.recognizeCallCount == 1 }

        viewModel.cancelTranscription()
        await waitUntil("the recogniser to observe cancellation") { transcriber.sawCancellation }
        await settle()

        XCTAssertNil(viewModel.error, "cancelling put an error on screen")
    }

    /// Cancel, then start again. The first run is still unwinding while the
    /// second is getting going, and it must not switch off a spinner that now
    /// belongs to the second.
    func testRestartingAfterCancelKeepsTheNewRunVisible() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, editedText: "kept")

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        viewModel.startTranscription()
        await waitUntil("the first run to start") { transcriber.recognizeCallCount == 1 }

        viewModel.cancelTranscription()
        viewModel.startTranscription()
        await waitUntil("the second run to start") { transcriber.recognizeCallCount == 2 }
        await settle()

        XCTAssertTrue(
            viewModel.isProcessing,
            "the cancelled run switched off the new run's spinner"
        )

        viewModel.cancelTranscription()
    }
}
