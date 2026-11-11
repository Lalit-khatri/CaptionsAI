@testable import CaptionsAI
import SwiftData
import XCTest

/// The editor's "Detected: … · Change" chip and the re-transcription behind
/// it.
@MainActor
final class DetectedLanguageTests: XCTestCase {
    private let kannada = TranscriptionLanguage.with(code: "kn")!
    private let telugu = TranscriptionLanguage.with(code: "te")!

    private func makeProject(in context: ModelContext) throws -> Project {
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: 10)
        context.insert(project)
        try context.save()
        return project
    }

    // MARK: - What the editor shows

    func testTheEditorShowsWhatAutoDetectHeard() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .succeed([CaptionSegment(startTime: 0, endTime: 1, text: "ನಮಸ್ಕಾರ")])
        transcriber.detection = LanguageDetection(language: kannada, confidence: 0.9)

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        await viewModel.generateCaptions()

        XCTAssertEqual(viewModel.detection?.language, kannada)
    }

    func testAChosenLanguageShowsNoChip() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .succeed([CaptionSegment(startTime: 0, endTime: 1, text: "hi")])

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        await viewModel.generateCaptions()

        XCTAssertNil(viewModel.detection)
    }

    func testAFailedRunShowsNoChip() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))
        let transcriber = FakeTranscriber()
        transcriber.behaviour = .fail(SpeechError.noSpeechDetected)
        transcriber.detection = LanguageDetection(language: kannada, confidence: 0.9)

        let viewModel = EditorViewModel(project: project, speechRecognizer: transcriber)
        await viewModel.generateCaptions()

        XCTAssertNil(viewModel.detection)
    }

    // MARK: - Changing it

    func testChangingTheLanguageTranscribesAgainInThatLanguage() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))
        let detecting = FakeTranscriber()
        detecting.behaviour = .succeed([CaptionSegment(startTime: 0, endTime: 1, text: "wrong guess")])
        detecting.detection = LanguageDetection(language: kannada, confidence: 0.4)

        let corrected = FakeTranscriber()
        corrected.behaviour = .succeed([CaptionSegment(startTime: 0, endTime: 1, text: "తెలుగు")])
        var requested: [TranscriptionLanguage] = []

        let viewModel = EditorViewModel(
            project: project,
            speechRecognizer: detecting,
            transcriberFactory: { language in
                requested.append(language)
                return corrected
            }
        )
        await viewModel.generateCaptions()

        viewModel.retranscribe(in: telugu)
        XCTAssertNil(viewModel.detection, "the chip stayed up after the user chose a language")
        await waitUntil("re-transcription to finish") { project.sortedSegments.map(\.text) == ["తెలుగు"] }

        XCTAssertEqual(requested, [telugu])
        XCTAssertNil(viewModel.detection)
    }

    func testChangingTheLanguageLeavesTheRememberedChoiceAlone() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let project = try makeProject(in: ModelContext(container))
        let suite = "DetectedLanguageTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LanguagePreference(defaults: defaults).language = .autoDetect

        let viewModel = EditorViewModel(
            project: project,
            speechRecognizer: FakeTranscriber(),
            transcriberFactory: { _ in FakeTranscriber() }
        )
        viewModel.retranscribe(in: telugu)

        XCTAssertEqual(LanguagePreference(defaults: defaults).language, .autoDetect)
    }

    // MARK: - Copy

    func testTheChipNamesTheLanguage() {
        XCTAssertEqual(
            DetectedLanguageChip.text(for: LanguageDetection(language: kannada, confidence: 0.9)),
            "Detected: Kannada"
        )
    }

    func testAnUnsureGuessIsShownAsAQuestion() {
        XCTAssertEqual(
            DetectedLanguageChip.text(for: LanguageDetection(language: kannada, confidence: 0.3)),
            "Detected: Kannada?"
        )
    }

    func testTheConfirmationSaysEditsWillBeLost() {
        XCTAssertEqual(EditorView.retranscribeTitle(for: telugu), "Re-transcribe in Telugu?")
        XCTAssertEqual(EditorView.retranscribeMessage, "This replaces the current captions, including any edits.")
    }
}
