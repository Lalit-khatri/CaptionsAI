@testable import CaptionsAI
import SwiftData
import XCTest

/// The editor's handling of a recogniser that has to get ready first, as
/// Whisper does when its model is not on the phone yet.
@MainActor
final class TranscriptionPreparationTests: XCTestCase {
    private func makeProject(in context: ModelContext) throws -> Project {
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: 10)
        context.insert(project)
        try context.save()
        return project
    }

    func testASlowModelDownloadIsNotCutOffByTheTranscriptionDeadline() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))

        let transcriber = FakeTranscriber()
        transcriber.prepareDuration = 0.3
        transcriber.behaviour = .succeed([CaptionSegment(startTime: 0, endTime: 1, text: "ನಮಸ್ಕಾರ")])

        // The deadline is a sixth of the preparation time. Were preparation
        // inside it, this would end in "took too long".
        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber, transcriptionBudget: 0.05)
        await viewModel.generateCaptions()

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(project.sortedSegments.map(\.text), ["ನಮಸ್ಕಾರ"])
        XCTAssertEqual(transcriber.prepareCallCount, 1)
    }

    func testAFailedPreparationIsShownAndRecognitionIsNotAttempted() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))

        let transcriber = FakeTranscriber()
        transcriber.prepareError = SpeechError.modelUnavailable(FakeDownloadError())

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        await viewModel.generateCaptions()

        XCTAssertEqual(viewModel.error, SpeechError.modelUnavailable(FakeDownloadError()).localizedDescription)
        XCTAssertEqual(transcriber.recognizeCallCount, 0)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testCancellingDuringPreparationIsQuiet() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))

        let transcriber = FakeTranscriber()
        transcriber.prepareDuration = 5

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        let run = Task { await viewModel.generateCaptions() }
        await waitUntil("preparation to start") { transcriber.prepareCallCount == 1 }
        run.cancel()
        _ = await run.result

        XCTAssertNil(viewModel.error, "cancelling put an error on screen")
        XCTAssertEqual(transcriber.recognizeCallCount, 0)
    }
}
