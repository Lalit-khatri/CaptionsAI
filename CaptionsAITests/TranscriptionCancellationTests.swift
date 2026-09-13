@testable import CaptionsAI
import SwiftData
import XCTest

/// What happens to the user's captions when transcription is cancelled.
///
/// `generateCaptions()` replaces the project's captions wholesale once the
/// recogniser returns:
///
///     project.segments.removeAll()
///
/// Nothing guards that, so a result arriving *after* the user cancelled is
/// applied regardless, and whatever they typed while it was running is
/// detached from the project — gone from their screen, with no undo.
///
/// Measured, so that the comment does not outrun the evidence: the orphaned
/// caption is **not** hard-deleted despite the `.cascade` delete rule. Before
/// the fix this test observed the store holding
/// `["a caption the user typed", "machine transcript"]` — the user's row
/// survives, detached, while the cancelled run's output is written anyway.
///
/// The assertions read both the project *and* the `ModelContext`. The view
/// model's in-memory array and the persisted rows are exactly the two things
/// that can disagree here, and only reading both tells you which.
@MainActor
final class TranscriptionCancellationTests: XCTestCase {

    private func makeProject(
        in context: ModelContext,
        editedText: String
    ) throws -> Project {
        let project = Project(
            name: "Test",
            videoURL: TestSupport.placeholderVideoURL
        )
        context.insert(project)
        project.addSegment(
            CaptionSegment(startTime: 0, endTime: 1, text: editedText)
        )
        try context.save()
        return project
    }

    private func persistedCaptionTexts(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<CaptionSegment>()).map(\.text)
    }

    /// The one that matters: the user walks away mid-transcription, the
    /// recogniser finishes anyway, and their edits must survive it.
    func testLateDeliveryAfterCancellationKeepsTheUsersEdits() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, editedText: "a caption the user typed")

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .deliverAfterCancellation([
            CaptionSegment(startTime: 0, endTime: 1, text: "machine transcript"),
        ])

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        let task = Task { await viewModel.generateCaptions() }

        await waitUntil("transcription to start") { transcriber.recognizeCallCount == 1 }
        task.cancel()
        await task.value

        XCTAssertEqual(
            project.sortedSegments.map(\.text),
            ["a caption the user typed"],
            "a cancelled transcription replaced the captions the user had typed"
        )
        XCTAssertEqual(
            try persistedCaptionTexts(context).sorted(),
            ["a caption the user typed"],
            "a cancelled transcription wrote its result to the store anyway"
        )
    }

    /// A run cancelled out from under `generateCaptions()` must leave the
    /// store alone and must not report the cancellation as a failure.
    ///
    /// It deliberately does *not* clear `isProcessing`. That belongs to
    /// `cancelTranscription()`, because by the time a cancelled run unwinds a
    /// newer one may already own the spinner — see `CancelButtonTests`.
    func testCancellationIsNotReportedAsAnError() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, editedText: "kept")

        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        let task = Task { await viewModel.generateCaptions() }

        await waitUntil("transcription to start") { transcriber.recognizeCallCount == 1 }
        task.cancel()
        await task.value

        XCTAssertNil(viewModel.error, "cancelling was reported to the user as a failure")
        XCTAssertTrue(transcriber.sawCancellation, "the transcriber never observed cancellation")
        XCTAssertEqual(try persistedCaptionTexts(context), ["kept"])
    }
}
