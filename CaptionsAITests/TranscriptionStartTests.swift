@testable import CaptionsAI
import SwiftData
import XCTest

/// What the editor does on open when it cannot or may not transcribe.
@MainActor
final class TranscriptionStartTests: XCTestCase {
    func testOpeningAProjectWhoseVideoIsGoneDoesNotTryToTranscribe() async {
        let project = Project(
            name: "Gone",
            videoURL: URL(fileURLWithPath: "/tmp/captionsai-absent-\(UUID().uuidString).mov")
        )
        let transcriber = FakeTranscriber()
        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        XCTAssertTrue(viewModel.videoIsMissing)

        viewModel.transcribeIfNeeded()
        await settle()

        XCTAssertNil(viewModel.error, "an error alert went up over the missing-video screen")
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(transcriber.authorizationCallCount, 0)
    }

    func testARefusedPermissionSaysWhereToTurnItOn() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: 10)
        context.insert(project)
        let transcriber = FakeTranscriber()
        transcriber.isAuthorized = false

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        await viewModel.generateCaptions()

        XCTAssertEqual(viewModel.error, "Speech recognition not authorized. Please enable it in Settings.")
    }
}
