import AVFoundation
import Foundation
import Speech

// MARK: - Speech Error

/// Errors that can occur during speech recognition.
enum SpeechError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case noSpeechDetected
    case audioExtractionFailed
    case recognitionFailed(Error)
    /// The recogniser neither finished nor failed within the time the editor
    /// was willing to give it.
    case timedOut
    /// The speech model for the chosen language could not be downloaded or
    /// loaded.
    case modelUnavailable(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable it in Settings."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .noSpeechDetected:
            return "No speech detected in this video. You can add captions manually."
        case .audioExtractionFailed:
            return "Failed to extract audio from the video."
        case let .recognitionFailed(error):
            return "Speech recognition failed: \(error.localizedDescription)"
        case .timedOut:
            return "Transcription took too long and was stopped. Check your connection and try again."
        case .modelUnavailable:
            return "Couldn't get the speech model for this language. Check your connection and try again."
        }
    }
}

// MARK: - Progress Checkpoints

/// Fraction reported once the audio track has been extracted.
let kProgressAudioExtracted: Double = 0.3
/// Fraction reported once recognition is done and grouping begins.
let kProgressTranscribed: Double = 0.9

// MARK: - Recognition Callback

/// What one call of the recogniser's result handler means for the caller
/// waiting on it.
enum RecognitionOutcome<Result> {
    /// A partial result: keep waiting for the final one.
    case waiting
    /// The final result.
    case finished(Result)
    /// The recogniser gave up, or broke its own contract.
    case failed(SpeechError)
}

/// Lets exactly one of several racing callers through.
///
/// A continuation resumed twice crashes, and the recogniser's handler can be
/// called again after it has delivered a final result or an error. A plain
/// `var` was used for this before; the lock makes the claim safe whichever
/// queue the handler happens to run on.
final class OneShotClaim: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.withLock {
            guard !isClaimed else { return false }
            isClaimed = true
            return true
        }
    }
}

/// Carries a Swift task's cancellation to work that is not a Swift task.
///
/// The recogniser task and the asset reader are only created partway through
/// their `withTaskCancellationHandler` body, and cancellation can arrive
/// before or after that. Whichever comes second runs the cancel action,
/// exactly once.
final class CancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Runs `cancel` now if cancellation already arrived, otherwise when it
    /// does. Attaching a second action replaces the first.
    func attach(_ cancel: @escaping () -> Void) {
        let runNow: Bool = lock.withLock {
            if cancelled { return true }
            action = cancel
            return false
        }
        if runNow { cancel() }
    }

    /// Marks the gate cancelled and runs the attached action, if any. Later
    /// calls do nothing.
    func cancel() {
        let pending: (() -> Void)? = lock.withLock {
            guard !cancelled else { return nil }
            cancelled = true
            defer { action = nil }
            return action
        }
        pending?()
    }
}

// MARK: - SpeechRecognizer

/// Wraps Apple's Speech framework to extract word-level captions from video audio.
@Observable
final class SpeechRecognizer {
    // MARK: - State

    var isProcessing = false
    var progress: Double = 0
    var partialResults: [String] = []
    var error: SpeechError?

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?

    // MARK: - Init

    init(locale: Locale = .init(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Main Recognition Pipeline

    /// Extracts speech from a video file and returns timed caption segments.
    @MainActor
    func recognizeSpeech(from videoURL: URL) async throws -> [CaptionSegment] {
        isProcessing = true
        progress = 0
        partialResults = []
        error = nil

        defer { isProcessing = false }

        guard let recognizer, recognizer.isAvailable else {
            let err = SpeechError.notAvailable
            error = err
            throw err
        }

        // Step 1: Extract audio track
        progress = 0.1
        let audioURL: URL
        do {
            audioURL = try await Self.extractAudioTrack(from: videoURL)
        } catch is CancellationError {
            // The user left. Not a failure to report.
            throw CancellationError()
        } catch {
            let err = SpeechError.audioExtractionFailed
            self.error = err
            throw err
        }
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Step 2: Recognize speech
        progress = kProgressAudioExtracted
        let clipDuration = (try? await AVURLAsset(url: videoURL).load(.duration).seconds) ?? 0
        let request = Self.configureRecognitionRequest(
            for: audioURL,
            supportsOnDevice: recognizer.supportsOnDeviceRecognition
        )

        // Cancelling the Swift task used to cancel nothing: the recogniser
        // kept working on a WAV file the `defer` above was about to delete,
        // and its result was thrown away. Now the recognition task is
        // cancelled with it and the caller gets `CancellationError` at once.
        try Task.checkCancellation()
        let gate = CancellationGate()
        let result: SFSpeechRecognitionResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let once = OneShotClaim()
                let task = recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
                    if let self, let result {
                        // Update partial results on main thread
                        let transcription = result.bestTranscription
                        let words = transcription.segments.map(\.substring)
                        let heard = transcription.segments.last.map { $0.timestamp + $0.duration } ?? 0
                        Task { @MainActor in
                            self.partialResults = words
                            self.progress = Self.recognitionProgress(heard: heard, of: clipDuration)
                        }
                    }

                    // Deliberately not behind `self`: returning early when the
                    // recogniser object was gone left this continuation, and the
                    // caller awaiting it, suspended for ever.
                    switch Self.recognitionOutcome(
                        result: result,
                        isFinal: result?.isFinal ?? false,
                        error: recognitionError
                    ) {
                    case .waiting:
                        break
                    case let .finished(final):
                        if once.claim() { continuation.resume(returning: final) }
                    case let .failed(failure):
                        // A cancelled task reports an error of its own; the
                        // caller should see the cancellation, not a failure.
                        let thrown: Error = gate.isCancelled ? CancellationError() : failure
                        if once.claim() { continuation.resume(throwing: thrown) }
                    }
                }
                // Resumed here as well, not only from the handler, so that
                // cancellation cannot hang on a recogniser that goes quiet.
                gate.attach {
                    task.cancel()
                    if once.claim() { continuation.resume(throwing: CancellationError()) }
                }
            }
        } onCancel: {
            gate.cancel()
        }

        // Step 3: Group into segments
        progress = kProgressTranscribed
        let transcriptionSegments = result.bestTranscription.segments

        guard !transcriptionSegments.isEmpty else {
            let err = SpeechError.noSpeechDetected
            error = err
            throw err
        }

        let captionSegments = CaptionGrouping.segments(from: Self.wordTimings(from: transcriptionSegments))
        progress = 1.0

        return captionSegments
    }

    // MARK: - Recognition Outcome

    /// Reads one call of the recogniser's result handler.
    ///
    /// The error is checked first, the way the compiler does for the
    /// continuations it synthesises for Objective-C APIs. The handler used to
    /// look at the result first and only consider the error when there was no
    /// result, so a partial result delivered alongside an error was treated as
    /// "keep waiting", and nothing further ever came: the spinner ran until
    /// the editor's timeout.
    ///
    /// No result and no error breaks the recogniser's contract. Waiting would
    /// hang, so it fails instead, as "no speech", which offers the user the
    /// way forward that is actually open to them: adding captions by hand.
    static func recognitionOutcome<Result>(
        result: Result?,
        isFinal: Bool,
        error: Error?
    ) -> RecognitionOutcome<Result> {
        if let error { return .failed(.recognitionFailed(error)) }
        guard let result else { return .failed(.noSpeechDetected) }
        return isFinal ? .finished(result) : .waiting
    }

    // MARK: - Progress

    /// How far along the recognition stage is, given that the recogniser has
    /// reported words up to `heard` seconds of a clip `duration` seconds long.
    ///
    /// This used to be `0.6 * words.count / max(words.count, 1)`, whose
    /// denominator is its own numerator: the answer was 0.9 for any non-empty
    /// result. The ring jumped to 90% on the first recognised word and stayed
    /// there for the whole of the longest stage, which reads as a hang.
    ///
    /// A clip of unknown length reports the stage's starting value rather than
    /// dividing by zero — a NaN here would reach a `ProgressView`.
    ///
    /// The result is clamped rather than just the fraction: in binary floating
    /// point `0.3 + 0.6 * 1.0` is a hair over `0.9`, and the next stage setting
    /// the ring to exactly `0.9` would be a step backwards.
    static func recognitionProgress(heard: Double, of duration: Double) -> Double {
        guard duration > 0 else { return kProgressAudioExtracted }
        let fraction = min(max(heard / duration, 0), 1)
        let reached = kProgressAudioExtracted + (kProgressTranscribed - kProgressAudioExtracted) * fraction
        return min(reached, kProgressTranscribed)
    }

    // MARK: - Audio Extraction

    /// Extracts the audio track from a video and saves as a WAV file.
    static func extractAudioTrack(from videoURL: URL) async throws -> URL {
        try Task.checkCancellation()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let gate = CancellationGate()

        do {
            let asset = AVURLAsset(url: videoURL)

            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw SpeechError.audioExtractionFailed
            }

            // Configure reader
            let reader = try AVAssetReader(asset: asset)
            let readerSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
            guard reader.canAdd(readerOutput) else {
                throw SpeechError.audioExtractionFailed
            }
            reader.add(readerOutput)

            // Configure writer
            let writer = try AVAssetWriter(url: outputURL, fileType: .wav)
            let writerSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            guard writer.canAdd(writerInput) else {
                throw SpeechError.audioExtractionFailed
            }
            writer.add(writerInput)

            // Process
            guard reader.startReading() else {
                throw reader.error ?? SpeechError.audioExtractionFailed
            }
            guard writer.startWriting() else {
                reader.cancelReading()
                throw writer.error ?? SpeechError.audioExtractionFailed
            }
            writer.startSession(atSourceTime: .zero)

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let queue = DispatchQueue(label: "audio.extraction")
                    let lock = NSLock()
                    var hasResumed = false

                    func finish(throwing error: Error?) {
                        lock.lock()
                        guard !hasResumed else {
                            lock.unlock()
                            return
                        }
                        hasResumed = true
                        lock.unlock()

                        writerInput.markAsFinished()
                        if let error {
                            writer.cancelWriting()
                            reader.cancelReading()
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }

                    writerInput.requestMediaDataWhenReady(on: queue) {
                        while writerInput.isReadyForMoreMediaData {
                            var bufferToAppend: CMSampleBuffer?
                            var isFinished = false

                            autoreleasepool {
                                if reader.status == .reading {
                                    if let buffer = readerOutput.copyNextSampleBuffer() {
                                        bufferToAppend = buffer
                                    } else {
                                        isFinished = true
                                    }
                                } else {
                                    isFinished = true
                                }
                            }

                            if let buffer = bufferToAppend {
                                if !writerInput.append(buffer) {
                                    finish(throwing: writer.error ?? SpeechError.audioExtractionFailed)
                                    return
                                }
                            } else if isFinished {
                                if reader.status == .completed {
                                    finish(throwing: nil)
                                } else {
                                    finish(throwing: reader.error ?? SpeechError.audioExtractionFailed)
                                }
                                return
                            }
                        }
                    }

                    // Leaving the editor used to let a long clip's extraction run
                    // to the end. `finish` goes through the same serial queue as
                    // the copy loop, so it never races an `append`.
                    gate.attach {
                        reader.cancelReading()
                        queue.async { finish(throwing: CancellationError()) }
                    }
                }
            } onCancel: {
                gate.cancel()
            }

            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? SpeechError.audioExtractionFailed
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 44 else {
                throw SpeechError.audioExtractionFailed
            }

            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if error is CancellationError || gate.isCancelled {
                throw CancellationError()
            }
            if let speechError = error as? SpeechError {
                throw speechError
            }
            throw SpeechError.audioExtractionFailed
        }
    }

    // MARK: - Recognition Request Configuration

    /// Configures an `SFSpeechURLRecognitionRequest` with the appropriate settings,
    /// requesting on-device recognition when supported to fulfill the app's privacy guarantee.
    static func configureRecognitionRequest(
        for audioURL: URL,
        supportsOnDevice: Bool
    ) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if supportsOnDevice {
            request.requiresOnDeviceRecognition = true
        }
        return request
    }

    // MARK: - Segment Grouping

    /// The recogniser's words as the timings `CaptionGrouping` splits.
    static func wordTimings(from transcriptionSegments: [SFTranscriptionSegment]) -> [WordTiming] {
        transcriptionSegments.map {
            WordTiming(word: $0.substring, startTime: $0.timestamp, endTime: $0.timestamp + $0.duration)
        }
    }
}
