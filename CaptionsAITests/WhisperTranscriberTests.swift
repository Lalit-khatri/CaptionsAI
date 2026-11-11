@testable import CaptionsAI
import Foundation
import XCTest

// MARK: - Pipeline fakes

final class FakeWhisperPipeline: WhisperPipeline, @unchecked Sendable {
    enum Behaviour {
        case words([WordTiming])
        case fail(Error)
        /// Decodes until told to stop, then returns what it has, the way
        /// WhisperKit does when its callback returns false.
        case decodeUntilStopped([WordTiming])
    }

    private let lock = NSLock()
    private var _languages: [String] = []
    private var _sawStop = false
    private var _detectCallCount = 0
    let behaviour: Behaviour
    let segmentsToReport: [(Double, String)]
    /// What `detectLanguage` answers, or throws.
    let detected: Result<(code: String, confidence: Double), Error>

    init(
        _ behaviour: Behaviour,
        reporting segments: [(Double, String)] = [],
        detects detected: Result<(code: String, confidence: Double), Error> = .success(("en", 1))
    ) {
        self.behaviour = behaviour
        segmentsToReport = segments
        self.detected = detected
    }

    var detectCallCount: Int { lock.withLock { _detectCallCount } }

    func detectLanguage(audioPath _: String) async throws -> (code: String, confidence: Double) {
        lock.withLock { _detectCallCount += 1 }
        return try detected.get()
    }

    var languages: [String] { lock.withLock { _languages } }
    var sawStop: Bool { lock.withLock { _sawStop } }

    func transcribe(
        audioPath _: String,
        language: String,
        shouldContinue: @escaping @Sendable () -> Bool,
        onSegment: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [WordTiming] {
        lock.withLock { _languages.append(language) }
        for (end, text) in segmentsToReport {
            onSegment(end, text)
        }
        switch behaviour {
        case let .words(words):
            return words
        case let .fail(error):
            throw error
        case let .decodeUntilStopped(words):
            while shouldContinue() {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            lock.withLock { _sawStop = true }
            return words
        }
    }
}

struct FakeWhisperLoader: WhisperPipelineLoading {
    var pipeline: FakeWhisperPipeline?
    var failure: Error?

    func load(modelFolder _: URL) async throws -> any WhisperPipeline {
        if let failure { throw failure }
        return pipeline!
    }
}

struct FakeLoadError: Error {}
struct FakeAudioError: Error {}

// MARK: - Tests

@MainActor
final class WhisperTranscriberTests: XCTestCase {
    private var sandbox: WhisperTestSandbox!
    private let kannada = TranscriptionLanguage.with(code: "kn")!
    private let video = URL(fileURLWithPath: "/nonexistent/clip.mov")

    override func setUp() {
        super.setUp()
        sandbox = WhisperTestSandbox()
    }

    override func tearDown() {
        sandbox.tearDown()
        super.tearDown()
    }

    /// A transcriber whose audio "extraction" writes a scratch file, so the
    /// cleanup after a run has something real to delete.
    private func makeTranscriber(
        language: TranscriptionLanguage? = nil,
        pipeline: FakeWhisperPipeline? = nil,
        loadFailure: Error? = nil,
        downloader: FakeWhisperDownloader = FakeWhisperDownloader(),
        audioFailure: Error? = nil,
        audioFile: URL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    ) -> WhisperTranscriber {
        WhisperTranscriber(
            language: language ?? kannada,
            store: sandbox.makeStore(downloader: downloader),
            loader: FakeWhisperLoader(pipeline: pipeline, failure: loadFailure),
            extractAudio: { _ in
                if let audioFailure { throw audioFailure }
                FileManager.default.createFile(atPath: audioFile.path, contents: Data([0]))
                return audioFile
            },
            clipDuration: { _ in 10 }
        )
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> WordTiming {
        WordTiming(word: text, startTime: start, endTime: end)
    }

    // MARK: - Routing

    func testEnglishIsTranscribedByApplesRecogniser() {
        XCTAssertTrue(EditorViewModel.makeTranscriber(for: .english) is SpeechRecognizer)
    }

    func testKannadaIsTranscribedByWhisper() {
        let transcriber = EditorViewModel.makeTranscriber(for: kannada)
        XCTAssertEqual((transcriber as? WhisperTranscriber)?.language, kannada)
    }

    func testWhisperNeedsNoSpeechPermission() async {
        let authorized = await makeTranscriber().requestAuthorization()
        XCTAssertTrue(authorized)
    }

    // MARK: - Recognition

    func testWhispersWordsBecomeCaptions() async throws {
        let pipeline = FakeWhisperPipeline(.words([
            word(" ನಮಸ್ಕಾರ", 0.0, 0.6),
            word(" ಎಲ್ಲರಿಗೂ", 0.6, 1.2),
        ]))
        let segments = try await makeTranscriber(pipeline: pipeline).recognizeSpeech(from: video)

        XCTAssertEqual(segments.map(\.text), ["ನಮಸ್ಕಾರ ಎಲ್ಲರಿಗೂ"])
        XCTAssertEqual(segments.first?.words.map(\.word), ["ನಮಸ್ಕಾರ", "ಎಲ್ಲರಿಗೂ"])
        XCTAssertEqual(segments.first?.startTime, 0)
        XCTAssertEqual(segments.first?.endTime, 1.2)
    }

    func testWhisperIsAskedForTheChosenLanguage() async throws {
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]))
        _ = try await makeTranscriber(pipeline: pipeline).recognizeSpeech(from: video)
        XCTAssertEqual(pipeline.languages, ["kn"])
    }

    func testTheFirstRunDownloadsTheModel() async throws {
        let downloader = FakeWhisperDownloader()
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]))
        _ = try await makeTranscriber(pipeline: pipeline, downloader: downloader).recognizeSpeech(from: video)
        XCTAssertEqual(downloader.callCount, 1)
    }

    func testNothingButSilenceIsNoSpeech() async {
        let pipeline = FakeWhisperPipeline(.words([word("  ", 0, 1), word("<|nocaptions|>", 1, 2)]))
        do {
            _ = try await makeTranscriber(pipeline: pipeline).recognizeSpeech(from: video)
            XCTFail("expected no speech")
        } catch SpeechError.noSpeechDetected {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTheExtractedAudioIsDeletedAfterwards() async throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]))
        _ = try await makeTranscriber(pipeline: pipeline, audioFile: audio).recognizeSpeech(from: video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testDecodedSegmentsFeedTheProgressScreen() async throws {
        let pipeline = FakeWhisperPipeline(
            .words([word("ನಮಸ್ಕಾರ", 0, 1)]),
            reporting: [(5, " ನಮಸ್ಕಾರ ಎಲ್ಲರಿಗೂ")]
        )
        let transcriber = makeTranscriber(pipeline: pipeline)
        _ = try await transcriber.recognizeSpeech(from: video)
        await waitUntil("live words to arrive") { transcriber.partialResults == ["ನಮಸ್ಕಾರ", "ಎಲ್ಲರಿಗೂ"] }
        XCTAssertEqual(transcriber.progress, 1)
    }

    // MARK: - Failures

    func testAFailedDownloadSaysTheModelIsUnavailable() async {
        let transcriber = makeTranscriber(downloader: FakeWhisperDownloader(failure: FakeDownloadError()))
        do {
            try await transcriber.prepare()
            XCTFail("expected a failure")
        } catch SpeechError.modelUnavailable {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAModelThatWillNotLoadSaysTheModelIsUnavailable() async {
        let transcriber = makeTranscriber(loadFailure: FakeLoadError())
        do {
            try await transcriber.prepare()
            XCTFail("expected a failure")
        } catch SpeechError.modelUnavailable {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnreadableAudioIsAnExtractionFailure() async {
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]))
        do {
            _ = try await makeTranscriber(pipeline: pipeline, audioFailure: FakeAudioError()).recognizeSpeech(from: video)
            XCTFail("expected a failure")
        } catch SpeechError.audioExtractionFailed {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testADecodingErrorIsARecognitionFailure() async {
        let pipeline = FakeWhisperPipeline(.fail(FakeLoadError()))
        do {
            _ = try await makeTranscriber(pipeline: pipeline).recognizeSpeech(from: video)
            XCTFail("expected a failure")
        } catch SpeechError.recognitionFailed {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Cancellation

    func testCancellingStopsWhisperAndDiscardsItsPartialTranscript() async {
        let pipeline = FakeWhisperPipeline(.decodeUntilStopped([word("ನಮಸ್ಕಾರ", 0, 1)]))
        let transcriber = makeTranscriber(pipeline: pipeline)

        let run = Task { try await transcriber.recognizeSpeech(from: video) }
        await waitUntil("decoding to start") { pipeline.languages.count == 1 }
        run.cancel()

        let outcome = await run.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(pipeline.sawStop, "Whisper kept decoding after the user cancelled")
    }

    func testPreparationReportsTheDownloadThenTheLoad() async throws {
        let downloader = FakeWhisperDownloader(holds: true)
        let transcriber = makeTranscriber(
            pipeline: FakeWhisperPipeline(.words([])),
            downloader: downloader
        )
        XCTAssertNil(transcriber.preparation)

        let preparing = Task { try await transcriber.prepare() }
        await waitUntil("download progress to show") { transcriber.preparation == .downloading(fraction: 0.5) }
        downloader.release()
        try await preparing.value
        XCTAssertNil(transcriber.preparation, "the processing screen still says it is preparing")
    }

    // MARK: - Auto-detect

    func testAutoDetectTranscribesInTheLanguageWhisperHears() async throws {
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]), detects: .success(("kn", 0.83)))
        let transcriber = makeTranscriber(language: .autoDetect, pipeline: pipeline)

        _ = try await transcriber.recognizeSpeech(from: video)

        XCTAssertEqual(pipeline.languages, ["kn"], "Whisper was not asked for the detected language")
        XCTAssertEqual(transcriber.detection, LanguageDetection(language: kannada, confidence: 0.83))
    }

    func testAChosenLanguageIsNotDetected() async throws {
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]), detects: .success(("te", 0.9)))
        let transcriber = makeTranscriber(pipeline: pipeline)

        _ = try await transcriber.recognizeSpeech(from: video)

        XCTAssertEqual(pipeline.detectCallCount, 0)
        XCTAssertEqual(pipeline.languages, ["kn"])
        XCTAssertNil(transcriber.detection)
    }

    func testAutoDetectedEnglishStaysWithWhisper() async throws {
        // The model is loaded by the time the language is known; handing
        // over to Apple's recogniser would mean a permission prompt mid-run.
        let pipeline = FakeWhisperPipeline(.words([word("hello", 0, 1)]), detects: .success(("en", 0.97)))
        let transcriber = makeTranscriber(language: .autoDetect, pipeline: pipeline)

        let segments = try await transcriber.recognizeSpeech(from: video)

        XCTAssertEqual(pipeline.languages, ["en"])
        XCTAssertEqual(segments.map(\.text), ["hello"])
        XCTAssertEqual(transcriber.detection?.language, .english)
    }

    func testADetectedLanguageThePickerDoesNotListReadsAsEnglish() {
        XCTAssertEqual(WhisperTranscriber.detection(fromCode: "yue", confidence: 0.6).language, .english)
    }

    func testConfidenceIsKeptBetweenZeroAndOne() {
        XCTAssertEqual(WhisperTranscriber.detection(fromCode: "kn", confidence: 1.4).confidence, 1)
        XCTAssertEqual(WhisperTranscriber.detection(fromCode: "kn", confidence: -0.2).confidence, 0)
    }

    func testAFailedDetectionIsARecognitionFailure() async {
        let pipeline = FakeWhisperPipeline(.words([word("ನಮಸ್ಕಾರ", 0, 1)]), detects: .failure(FakeLoadError()))
        do {
            _ = try await makeTranscriber(language: .autoDetect, pipeline: pipeline).recognizeSpeech(from: video)
            XCTFail("expected a failure")
        } catch SpeechError.recognitionFailed {
            XCTAssertEqual(pipeline.languages, [], "transcribed without knowing the language")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Cleaning

    func testCleaningTrimsWhispersLeadingSpaces() {
        XCTAssertEqual(WhisperTranscriber.cleaned([word(" hello", 0, 1)]).map(\.word), ["hello"])
    }

    func testCleaningDropsSpecialTokensAndBlanks() {
        XCTAssertEqual(
            WhisperTranscriber.cleaned([word("<|kn|>", 0, 0), word(" ", 0, 1), word("ಹೌದು", 1, 2)]).map(\.word),
            ["ಹೌದು"]
        )
    }

    func testCleaningNeverLeavesAWordEndingBeforeItStarts() {
        let cleaned = WhisperTranscriber.cleaned([word("ಹೌದು", 2.0, 1.5)])
        XCTAssertEqual(cleaned.first?.endTime, 2.0)
    }
}
