@testable import CaptionsAI
import SwiftData
import XCTest

/// Commit 1.1's whole claim: the editor talks to an injected recognizer, and a
/// fake can drive it. No behaviour change — these tests exist to prove the seam
/// is real before the next commits start asserting through it.
@MainActor
final class EditorViewModelSeamTests: XCTestCase {
    private func makeProject(in container: ModelContainer) -> Project {
        let project = Project(
            name: "Seam",
            videoURL: URL(fileURLWithPath: "/tmp/does-not-need-to-exist.mp4")
        )
        container.mainContext.insert(project)
        return project
    }

    func testGenerateCaptionsUsesTheInjectedRecognizer() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = makeProject(in: container)

        let fake = FakeTranscriber()
        fake.behaviour = .succeed([
            CaptionSegment(startTime: 0, endTime: 1, text: "from the fake"),
        ])

        let viewModel = EditorViewModel(project: project, speechRecognizer: fake)
        await viewModel.generateCaptions()

        XCTAssertEqual(fake.authorizationCallCount, 1)
        XCTAssertEqual(fake.recognizeCallCount, 1)
        XCTAssertEqual(viewModel.segments.map(\.text), ["from the fake"])
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.error)
    }

    func testDeniedAuthorizationStopsBeforeRecognition() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = makeProject(in: container)

        let fake = FakeTranscriber()
        fake.isAuthorized = false

        let viewModel = EditorViewModel(project: project, speechRecognizer: fake)
        await viewModel.generateCaptions()

        XCTAssertEqual(fake.recognizeCallCount, 0)
        XCTAssertNotNil(viewModel.error)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testRecognitionFailureSurfacesAsAnError() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = makeProject(in: container)

        let fake = FakeTranscriber()
        fake.behaviour = .fail(SpeechError.noSpeechDetected)

        let viewModel = EditorViewModel(project: project, speechRecognizer: fake)
        await viewModel.generateCaptions()

        XCTAssertEqual(viewModel.error, SpeechError.noSpeechDetected.localizedDescription)
        XCTAssertFalse(viewModel.isProcessing)
    }
}
