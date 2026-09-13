import AVFoundation
import AVKit
import SwiftUI

// MARK: - EditorViewModel

/// Manages caption editing, style selection, and video playback.
@Observable
final class EditorViewModel {
    // MARK: - Position Constants

    /// Minimum Y position to prevent captions from going off-screen top
    private static let minCaptionY: Double = 0.08
    /// Maximum Y position to prevent captions from going off-screen bottom
    private static let maxCaptionY: Double = 0.92

    // MARK: - State

    var project: Project
    var segments: [CaptionSegment]
    var selectedStyle: CaptionStyle
    var selectedSegment: CaptionSegment?
    var isProcessing = false
    var processingProgress: Double = 0
    var currentPlaybackTime: Double = 0
    var error: String?

    // MARK: - Player

    var player: AVPlayer?
    var isPlaying = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // MARK: - Engine

    /// Injected so tests can drive the transcription lifecycle with a fake.
    /// Defaults to the real recognizer, so call sites are unchanged.
    let speechRecognizer: any Transcribing

    // MARK: - Init

    init(project: Project, speechRecognizer: any Transcribing = SpeechRecognizer()) {
        self.project = project
        self.speechRecognizer = speechRecognizer
        segments = project.sortedSegments
        selectedStyle = project.selectedStyle

        // Configure audio session for the video playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        if let url = project.videoURL {
            player = AVPlayer(url: url)
            observePlaybackEnd()
        }
    }

    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Playback End Observer

    /// Seeks back to the beginning when the video finishes so the next
    /// play tap restarts from the start.
    private func observePlaybackEnd() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.isPlaying = false
        }
    }

    // MARK: - Speech Recognition

    @MainActor
    func generateCaptions() async {
        guard let videoURL = project.videoURL else {
            error = "Video file not found"
            return
        }

        isProcessing = true
        error = nil

        do {
            let authorized = await speechRecognizer.requestAuthorization()
            guard authorized else {
                error = "Speech recognition not authorized"
                isProcessing = false
                return
            }

            let newSegments = try await speechRecognizer.recognizeSpeech(from: videoURL)

            // The recogniser can return after the user has cancelled and moved
            // on. Applying the result here would detach whatever captions they
            // typed while it was running, with no undo. Cancellation is not an
            // error the user needs told about, so return quietly rather than
            // throwing CancellationError into the catch below.
            guard !Task.isCancelled else {
                isProcessing = false
                return
            }

            // Clear existing segments and add new ones
            project.segments.removeAll()
            for segment in newSegments {
                project.addSegment(segment)
            }
            segments = project.sortedSegments

            AnalyticsService.captionsGenerated(
                wordCount: newSegments.reduce(0) { $0 + $1.words.count }
            )

        } catch let speechError as SpeechError {
            error = speechError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        isProcessing = false
    }

    // MARK: - Caption Editing

    func updateSegmentText(_ segment: CaptionSegment, newText: String) {
        segment.text = newText

        // Rebuild word timings to match the new text.
        // Distribute the segment's time range evenly across the new words
        // so word-by-word highlighting stays in sync.
        let newWords = newText.split(separator: " ").map(String.init)
        if !newWords.isEmpty {
            let segmentDuration = segment.endTime - segment.startTime
            let wordDuration = segmentDuration / Double(newWords.count)
            segment.words = newWords.enumerated().map { index, word in
                WordTiming(
                    word: word,
                    startTime: segment.startTime + Double(index) * wordDuration,
                    endTime: segment.startTime + Double(index + 1) * wordDuration
                )
            }
        } else {
            segment.words = []
        }

        project.modifiedAt = Date()
        segments = project.sortedSegments
    }

    func updateSegmentTiming(_ segment: CaptionSegment, start: Double, end: Double) {
        segment.startTime = start
        segment.endTime = end
        project.modifiedAt = Date()
        segments = project.sortedSegments
    }

    func addSegment(at time: Double, text: String = "New caption") {
        let segment = CaptionSegment(
            startTime: time,
            endTime: time + 2.0,
            text: text,
            sortOrder: segments.count
        )
        project.addSegment(segment)
        segments = project.sortedSegments
    }

    func deleteSegment(_ segment: CaptionSegment) {
        project.removeSegment(segment)
        segments = project.sortedSegments
        if selectedSegment?.id == segment.id {
            selectedSegment = nil
        }
    }

    // MARK: - Style Selection

    func selectStyle(_ style: CaptionStyle) {
        selectedStyle = style
        project.updateStyle(style.name)
    }

    // MARK: - Caption Position

    /// The effective Y position for captions (0.0–1.0), clamped to safe bounds
    var captionYPosition: Double {
        get { project.captionYPosition ?? selectedStyle.position.yPosition }
        set {
            let clamped = min(max(newValue, Self.minCaptionY), Self.maxCaptionY)
            project.updateCaptionPosition(clamped)
        }
    }

    // MARK: - Playback

    func setupTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentPlaybackTime = CMTimeGetSeconds(time)
        }
    }

    func seekTo(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Returns the active caption segment at the current playback time
    var activeSegment: CaptionSegment? {
        segments.first { $0.isActive(at: currentPlaybackTime) }
    }
}
