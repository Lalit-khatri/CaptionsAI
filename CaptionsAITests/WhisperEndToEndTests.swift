@testable import CaptionsAI
import AVFoundation
import XCTest

/// The real thing: downloads a Whisper model from Hugging Face, loads it with
/// WhisperKit and captions a video, through the same `WhisperTranscriber` the
/// editor uses.
///
/// Off by default, because it needs the network and a 75 MB download on a
/// fresh simulator. Run it with `CAPTIONSAI_WHISPER_E2E=1` in the test
/// action's environment.
///
/// Uses the multilingual `tiny` model rather than the `small` the app ships
/// with: same code path, a sixth of the download. The clip is WhisperKit's
/// own Spanish test recording (MIT), put in an H.264/AAC MP4 so that it goes
/// through the video audio extraction exactly as an imported video does.
final class WhisperEndToEndTests: XCTestCase {
    private static let enabled = ProcessInfo.processInfo.environment["CAPTIONSAI_WHISPER_E2E"] == "1"

    @MainActor
    func testARealWhisperModelCaptionsASpanishVideo() async throws {
        try XCTSkipUnless(Self.enabled, "set CAPTIONSAI_WHISPER_E2E=1 to download a model and run Whisper")

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperEndToEnd", isDirectory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WhisperEndToEndTests"))
        let store = WhisperModelStore(
            variant: "openai_whisper-tiny",
            downloader: WhisperKitDownloader(),
            defaults: defaults,
            baseDirectory: base
        )
        let transcriber = WhisperTranscriber(
            language: try XCTUnwrap(TranscriptionLanguage.with(code: "es")),
            store: store,
            loader: WhisperKitLoader(tokenizerFolder: base)
        )
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "spanish_speech", withExtension: "mp4"))
        let duration = try await AVURLAsset(url: video).load(.duration).seconds

        try await transcriber.prepare()
        let segments = try await transcriber.recognizeSpeech(from: video)

        let text = segments.map(\.text).joined(separator: " ")
        print("Whisper end-to-end transcript: \(text)")
        XCTAssertTrue(
            text.lowercased().hasPrefix("esta es una grabación"),
            "unexpected transcript: \(text)"
        )

        let words = segments.flatMap(\.words)
        XCTAssertFalse(words.isEmpty)
        XCTAssertEqual(words.map(\.startTime), words.map(\.startTime).sorted(), "word timings go backwards")
        XCTAssertTrue(words.allSatisfy { $0.startTime >= 0 && $0.endTime <= duration + 0.5 }, "a word is timed outside the clip")
        XCTAssertTrue(words.allSatisfy { $0.word == $0.word.trimmingCharacters(in: .whitespaces) })
        XCTAssertEqual(store.state, .downloaded)
    }
}
