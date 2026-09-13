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
        }
    }
}

// MARK: - Progress Checkpoints

/// Fraction reported once the audio track has been extracted.
let kProgressAudioExtracted: Double = 0.3
/// Fraction reported once recognition is done and grouping begins.
let kProgressTranscribed: Double = 0.9

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

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
                guard let self else { return }

                if let result {
                    // Update partial results on main thread
                    let transcription = result.bestTranscription
                    let words = transcription.segments.map(\.substring)
                    let heard = transcription.segments.last.map { $0.timestamp + $0.duration } ?? 0
                    Task { @MainActor in
                        self.partialResults = words
                        self.progress = Self.recognitionProgress(heard: heard, of: clipDuration)
                    }

                    if result.isFinal, !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: result)
                    }
                } else if let recognitionError, !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: SpeechError.recognitionFailed(recognitionError))
                }
            }
        }

        // Step 3: Group into segments
        progress = kProgressTranscribed
        let transcriptionSegments = result.bestTranscription.segments

        guard !transcriptionSegments.isEmpty else {
            let err = SpeechError.noSpeechDetected
            error = err
            throw err
        }

        let captionSegments = groupIntoSegments(transcriptionSegments)
        progress = 1.0

        return captionSegments
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
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

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

    /// Groups individual word timings into caption segments.
    /// Rules: max 8 words per segment, max 4 seconds duration.
    private func groupIntoSegments(_ transcriptionSegments: [SFTranscriptionSegment]) -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        var currentWords: [WordTiming] = []
        var segmentStartTime: Double = 0
        let maxWordsPerSegment = 8
        let maxDuration = 4.0

        for (index, tSegment) in transcriptionSegments.enumerated() {
            let wordTiming = WordTiming(
                word: tSegment.substring,
                startTime: tSegment.timestamp,
                endTime: tSegment.timestamp + tSegment.duration
            )

            if currentWords.isEmpty {
                segmentStartTime = tSegment.timestamp
            }

            currentWords.append(wordTiming)

            let duration = tSegment.timestamp + tSegment.duration - segmentStartTime
            let isLastWord = index == transcriptionSegments.count - 1

            if currentWords.count >= maxWordsPerSegment || duration >= maxDuration || isLastWord {
                let text = currentWords.map(\.word).joined(separator: " ")
                let endTime = tSegment.timestamp + tSegment.duration

                let segment = CaptionSegment(
                    startTime: segmentStartTime,
                    endTime: endTime,
                    text: text,
                    sortOrder: segments.count,
                    words: currentWords
                )
                segments.append(segment)
                currentWords = []
            }
        }

        return segments
    }
}
