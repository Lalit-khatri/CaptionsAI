@testable import CaptionsAI
import Foundation
import SwiftData
import XCTest

/// When the editor transcribes on its own, and when it must not.
///
/// `.task` runs on every appearance of the editor — including coming back
/// from Export or Preview — so "transcribe if there are no captions" alone
/// re-transcribed a project whose captions the user had deleted on purpose.
@MainActor
final class TranscribeOnAppearTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func makeEditor(
        captions: [String] = [],
        transcriber: FakeTranscriber
    ) throws -> (EditorViewModel, Project) {
        let reference = try VideoLibrary.store(data: Data("video".utf8))
        let url = try XCTUnwrap(VideoLibrary.resolve(reference))
        written.append(url)

        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: url)
        context.insert(project)
        for (index, text) in captions.enumerated() {
            project.addSegment(CaptionSegment(startTime: Double(index), endTime: Double(index) + 1, text: text))
        }
        try context.save()

        let editor = EditorViewModel(
            project: project,
            speechRecognizer: transcriber,
            audioSession: FakeAudioSession(),
            transcriptionBudget: 5
        )
        return (editor, project)
    }

    private func machineTranscript() -> [CaptionSegment] {
        [CaptionSegment(startTime: 0, endTime: 1, text: "machine transcript")]
    }

    // MARK: - First appearance

    func testAnEmptyProjectIsTranscribedOnFirstAppearance() async throws {
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .succeed(machineTranscript())
        let (editor, _) = try makeEditor(transcriber: transcriber)

        editor.transcribeIfNeeded()
        await waitUntil("transcription finished") { editor.hasFinishedTranscription }

        XCTAssertEqual(transcriber.recognizeCallCount, 1)
        XCTAssertEqual(editor.segments.map(\.text), ["machine transcript"])
    }

    func testAProjectWithCaptionsIsNotTranscribed() async throws {
        let transcriber = FakeTranscriber()
        let (editor, _) = try makeEditor(captions: ["already here"], transcriber: transcriber)

        editor.transcribeIfNeeded()
        await settle()

        XCTAssertEqual(transcriber.recognizeCallCount, 0)
        XCTAssertEqual(editor.segments.map(\.text), ["already here"])
    }

    // MARK: - Coming back

    /// The defect: delete every caption, visit Export, come back, and a new
    /// transcript appears that the user never asked for.
    func testDeletingEveryCaptionThenComingBackDoesNotTranscribeAgain() async throws {
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .succeed(machineTranscript())
        let (editor, _) = try makeEditor(transcriber: transcriber)
        editor.transcribeIfNeeded()
        await waitUntil("transcription finished") { editor.hasFinishedTranscription }

        for segment in editor.segments { editor.deleteSegment(segment) }
        editor.transcribeIfNeeded()
        await settle()

        XCTAssertEqual(transcriber.recognizeCallCount, 1)
        XCTAssertEqual(editor.segments.map(\.text), [])
    }

    /// A clip with no speech used to be re-transcribed, and the same error
    /// shown again, every time the editor came back.
    func testAFailedTranscriptionIsNotRetriedOnReturn() async throws {
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .fail(SpeechError.noSpeechDetected)
        let (editor, _) = try makeEditor(transcriber: transcriber)
        editor.transcribeIfNeeded()
        await waitUntil("transcription finished") { editor.hasFinishedTranscription }

        editor.transcribeIfNeeded()
        await settle()

        XCTAssertEqual(transcriber.recognizeCallCount, 1)
    }

    /// Leaving the editor cancels the run. It did not finish, so coming back
    /// tries again rather than leaving the user with nothing.
    func testARunCancelledByLeavingIsRetriedOnReturn() async throws {
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled
        let (editor, _) = try makeEditor(transcriber: transcriber)
        editor.transcribeIfNeeded()
        await waitUntil("recogniser started") { transcriber.recognizeCallCount == 1 }

        editor.cancelTranscription()
        await waitUntil("cancellation seen") { transcriber.sawCancellation }
        await settle()
        XCTAssertFalse(editor.hasFinishedTranscription)

        transcriber.behaviour = .succeed(machineTranscript())
        editor.transcribeIfNeeded()
        await waitUntil("second run finished") { editor.hasFinishedTranscription }

        XCTAssertEqual(transcriber.recognizeCallCount, 2)
        XCTAssertEqual(editor.segments.map(\.text), ["machine transcript"])
    }

    /// Two appearances in quick succession must not start two runs.
    func testAppearingTwiceWhileRunningStartsOneRun() async throws {
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .hangUntilCancelled
        let (editor, _) = try makeEditor(transcriber: transcriber)

        editor.transcribeIfNeeded()
        editor.transcribeIfNeeded()
        await settle()

        XCTAssertEqual(transcriber.recognizeCallCount, 1)
        editor.cancelTranscription()
    }

    func testARefusedPermissionIsNotAskedAgainOnReturn() async throws {
        let transcriber = FakeTranscriber()
        transcriber.isAuthorized = false
        let (editor, _) = try makeEditor(transcriber: transcriber)
        editor.transcribeIfNeeded()
        await waitUntil("transcription finished") { editor.hasFinishedTranscription }

        editor.transcribeIfNeeded()
        await settle()

        XCTAssertEqual(transcriber.authorizationCallCount, 1)
        XCTAssertEqual(transcriber.recognizeCallCount, 0)
    }
}
