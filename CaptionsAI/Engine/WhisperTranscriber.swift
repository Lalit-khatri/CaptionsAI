import AVFoundation
import Foundation

// MARK: - Seams

/// A loaded Whisper model, ready to transcribe.
///
/// The real one wraps WhisperKit (see `WhisperKitPipeline`). Kept behind a
/// protocol so everything `WhisperTranscriber` decides — cancellation, empty
/// results, cleaning up Whisper's words — is testable without a 466 MB model.
protocol WhisperPipeline: AnyObject, Sendable {
    /// Transcribes the 16 kHz audio at `audioPath`, spoken in `language`,
    /// into timed words.
    ///
    /// - Parameters:
    ///   - shouldContinue: Asked between decoding steps; returning false stops
    ///     early, and whatever was decoded so far is returned.
    ///   - onSegment: Called as each stretch of speech is decoded, with where
    ///     in the audio it ends, in seconds, and its text.
    func transcribe(
        audioPath: String,
        language: String,
        shouldContinue: @escaping @Sendable () -> Bool,
        onSegment: @escaping @Sendable (_ endSeconds: Double, _ text: String) -> Void
    ) async throws -> [WordTiming]
}

/// Loads a downloaded model into memory.
protocol WhisperPipelineLoading: Sendable {
    func load(modelFolder: URL) async throws -> any WhisperPipeline
}

// MARK: - WhisperTranscriber

/// Transcribes with Whisper, on-device, in any language Whisper knows.
///
/// Used for every language except English, on every supported iOS version;
/// see `TranscriptionLanguage.engine`. Audio is read with the same extractor
/// as Apple's path and the words are split into captions by the same
/// `CaptionGrouping`, so the editor cannot tell the two apart.
@Observable
final class WhisperTranscriber: Transcribing {
    var progress: Double = 0
    var partialResults: [String] = []

    let language: TranscriptionLanguage

    private let store: WhisperModelStore
    private let loader: any WhisperPipelineLoading
    private let extractAudio: @Sendable (URL) async throws -> URL
    private let clipDuration: @Sendable (URL) async -> Double

    private var pipeline: (any WhisperPipeline)?
    /// The recognition in progress, so a late live-feed update can tell it
    /// belongs to a run that has already finished.
    private var activeRun: UUID?
    private var isPreparing = false
    private var isLoading = false

    init(
        language: TranscriptionLanguage,
        store: WhisperModelStore = .shared,
        loader: any WhisperPipelineLoading = WhisperKitLoader(),
        extractAudio: @escaping @Sendable (URL) async throws -> URL = { try await SpeechRecognizer.extractAudioTrack(from: $0) },
        clipDuration: @escaping @Sendable (URL) async -> Double = { (try? await AVURLAsset(url: $0).load(.duration).seconds) ?? 0 }
    ) {
        self.language = language
        self.store = store
        self.loader = loader
        self.extractAudio = extractAudio
        self.clipDuration = clipDuration
    }

    // MARK: - Transcribing

    /// Whisper reads the audio file itself; nothing is sent to Apple's
    /// recogniser, so there is no Speech permission to ask for.
    func requestAuthorization() async -> Bool { true }

    var preparation: TranscriptionPreparation? {
        if isLoading { return .loading }
        guard isPreparing else { return nil }
        if case let .downloading(fraction) = store.state { return .downloading(fraction: fraction) }
        return nil
    }

    /// Downloads the model if it is not on the phone yet, then loads it.
    @MainActor
    func prepare() async throws {
        guard pipeline == nil else { return }
        isPreparing = true
        defer {
            isPreparing = false
            isLoading = false
        }

        let folder: URL
        do {
            folder = try await store.modelFolder()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechError.modelUnavailable(error)
        }

        try Task.checkCancellation()
        isLoading = true
        do {
            let loading = Task { [loader] in try await loader.load(modelFolder: folder) }
            pipeline = try await waitAbandoningOnCancel(loading)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechError.modelUnavailable(error)
        }
    }

    @MainActor
    func recognizeSpeech(from videoURL: URL) async throws -> [CaptionSegment] {
        progress = 0
        partialResults = []

        if pipeline == nil { try await prepare() }
        guard let pipeline else { throw SpeechError.notAvailable }
        // Let the model go once this run is over. Held between runs it is
        // several hundred MB the export that usually comes next could use.
        defer { self.pipeline = nil }

        progress = 0.1
        let audioURL: URL
        do {
            audioURL = try await extractAudio(videoURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechError.audioExtractionFailed
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        progress = kProgressAudioExtracted
        let duration = await clipDuration(videoURL)
        try Task.checkCancellation()

        let gate = CancellationGate()
        let feed = LiveFeed()
        let run = UUID()
        activeRun = run
        defer { activeRun = nil }

        let words: [WordTiming]
        do {
            words = try await withTaskCancellationHandler {
                try await pipeline.transcribe(
                    audioPath: audioURL.path,
                    language: language.code,
                    shouldContinue: { !gate.isCancelled },
                    onSegment: { [weak self] endSeconds, text in
                        feed.add(Self.words(in: text), heardUpTo: endSeconds)
                        Task { @MainActor in
                            // A hop that lands after the run has ended must
                            // not drag the finished ring back to 60%.
                            guard let self, self.activeRun == run, !gate.isCancelled else { return }
                            self.partialResults = feed.words
                            self.progress = SpeechRecognizer.recognitionProgress(heard: feed.heard, of: duration)
                        }
                    }
                )
            } onCancel: {
                gate.cancel()
            }
        } catch {
            if gate.isCancelled || error is CancellationError { throw CancellationError() }
            if let speechError = error as? SpeechError { throw speechError }
            throw SpeechError.recognitionFailed(error)
        }

        // Whisper stops early when told to and returns what it has. That is
        // a partial transcript of a run the user abandoned, not a result.
        if gate.isCancelled { throw CancellationError() }
        activeRun = nil
        partialResults = feed.words

        let cleaned = Self.cleaned(words)
        guard !cleaned.isEmpty else { throw SpeechError.noSpeechDetected }

        progress = kProgressTranscribed
        let segments = CaptionGrouping.segments(from: cleaned)
        progress = 1
        return segments
    }

    // MARK: - Cleaning

    /// Whisper's words as captions want them.
    ///
    /// Whisper marks a word boundary with a leading space, so words arrive as
    /// " ನಮಸ್ಕಾರ" and would be joined with double spaces. Special tokens
    /// ("<|kn|>") are dropped in case one slips through, as are words that
    /// are nothing but whitespace, and a word whose end precedes its start is
    /// given a zero length rather than a negative one.
    static func cleaned(_ words: [WordTiming]) -> [WordTiming] {
        words.compactMap { word in
            let text = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !(text.hasPrefix("<|") && text.hasSuffix("|>")) else { return nil }
            return WordTiming(word: text, startTime: word.startTime, endTime: max(word.endTime, word.startTime))
        }
    }

    /// The words of a decoded segment, for the live feed on the processing
    /// screen.
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

// MARK: - LiveFeed

/// What Whisper has decoded so far, collected from its callback thread for
/// the processing screen to show.
private final class LiveFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var _words: [String] = []
    private var _heard: Double = 0

    var words: [String] { lock.withLock { _words } }
    var heard: Double { lock.withLock { _heard } }

    func add(_ words: [String], heardUpTo seconds: Double) {
        lock.withLock {
            _words.append(contentsOf: words)
            _heard = max(_heard, seconds)
        }
    }
}
