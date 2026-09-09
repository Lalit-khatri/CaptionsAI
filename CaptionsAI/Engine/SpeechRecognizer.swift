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
        }
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
            audioURL = try await extractAudioTrack(from: videoURL)
        } catch {
            let err = SpeechError.audioExtractionFailed
            self.error = err
            throw err
        }

        // Step 2: Recognize speech
        progress = 0.3
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
                guard let self else { return }

                if let result {
                    // Update partial results on main thread
                    let words = result.bestTranscription.segments.map(\.substring)
                    Task { @MainActor in
                        self.partialResults = words
                        self.progress = 0.3 + (0.6 * Double(words.count) / max(Double(words.count), 1))
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
        progress = 0.9
        let transcriptionSegments = result.bestTranscription.segments

        guard !transcriptionSegments.isEmpty else {
            let err = SpeechError.noSpeechDetected
            error = err
            throw err
        }

        let captionSegments = groupIntoSegments(transcriptionSegments)
        progress = 1.0

        // Cleanup temp audio file
        try? FileManager.default.removeItem(at: audioURL)

        return captionSegments
    }

    // MARK: - Audio Extraction

    /// Extracts the audio track from a video and saves as a WAV file.
    private func extractAudioTrack(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SpeechError.audioExtractionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

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
        writer.add(writerInput)

        // Process
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.extraction")) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()
        return outputURL
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
