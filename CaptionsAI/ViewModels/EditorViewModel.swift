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

    /// The in-flight transcription, held so that `cancelTranscription()` has
    /// something to cancel. Driving this from the view's `.task` instead left
    /// the handle inside SwiftUI, out of reach of the Cancel button.
    private var transcriptionTask: Task<Void, Never>?

    /// Supplied by tests only. `nil` means "use the player", which is what the
    /// app always does.
    private let injectedPlaybackClock: (any PeriodicTimeObserving)?

    /// Whatever the periodic playback callback is registered with.
    private var playbackClock: (any PeriodicTimeObserving)? {
        if let injectedPlaybackClock { return injectedPlaybackClock }
        return player
    }

    // MARK: - Init

    init(
        project: Project,
        speechRecognizer: any Transcribing = SpeechRecognizer(),
        playbackClock: (any PeriodicTimeObserving)? = nil
    ) {
        self.project = project
        self.speechRecognizer = speechRecognizer
        injectedPlaybackClock = playbackClock
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
        transcriptionTask?.cancel()
        if let timeObserver {
            let clock: (any PeriodicTimeObserving)? = injectedPlaybackClock ?? player
            clock?.removePeriodicObserver(timeObserver)
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

    /// Starts transcription and keeps hold of the task.
    ///
    /// The view used to run `generateCaptions()` straight out of `.task`,
    /// which meant SwiftUI owned the only handle and the Cancel button could
    /// do nothing but set `isProcessing = false` — the spinner went away and
    /// the recogniser carried on.
    @MainActor
    func startTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.generateCaptions()
        }
    }

    /// Stops the running transcription. Safe to call when nothing is running.
    ///
    /// `isProcessing` is cleared here rather than left to `generateCaptions()`
    /// so the overlay goes as soon as the user taps, instead of waiting on a
    /// recogniser that may take a while to notice it has been cancelled.
    @MainActor
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isProcessing = false
    }

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
            //
            // `isProcessing` is deliberately left alone: whoever cancelled has
            // already cleared it, and a run started since owns it now.
            guard !Task.isCancelled else { return }

            // Replace the previous transcript. `removeAllSegments()` rather
            // than `segments.removeAll()`: the cascade rule only fires when the
            // project is deleted, so clearing the array left every previous
            // caption in the store with no parent, once per run.
            project.removeAllSegments()
            for segment in newSegments {
                project.addSegment(segment)
            }
            segments = project.sortedSegments

            AnalyticsService.captionsGenerated(
                wordCount: newSegments.reduce(0) { $0 + $1.words.count }
            )

        } catch is CancellationError {
            // The user asked for this. Reporting it as a failure would put an
            // error banner on screen for doing what they were told they could.
        } catch let speechError as SpeechError {
            error = speechError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        // Same reasoning as the guard above: a cancelled run must not switch
        // off a spinner it no longer owns.
        if !Task.isCancelled {
            isProcessing = false
        }
    }

    // MARK: - Caption Editing

    /// Applies an edit from the transcript sheet.
    ///
    /// One call rather than two, because the halves are not independent. Word
    /// timings are derived from the segment's range, so setting the text first
    /// — which is what the sheet used to do — spreads the new words across the
    /// range the caption is about to stop having. Retime a caption from 0–2s
    /// to 10–12s while also correcting its wording and every word timing stayed
    /// back at 0–2s, where nothing will ever highlight them: `activeWord(at:)`
    /// looks inside the segment's own range and finds nothing there.
    func updateSegment(_ segment: CaptionSegment, text: String, start: Double, end: Double) {
        segment.startTime = start
        segment.endTime = end
        applyText(text, to: segment)
        finishSegmentEdit()
    }

    func updateSegmentText(_ segment: CaptionSegment, newText: String) {
        applyText(newText, to: segment)
        finishSegmentEdit()
    }

    func updateSegmentTiming(_ segment: CaptionSegment, start: Double, end: Double) {
        // Rescale rather than redistribute. The words are unchanged, so their
        // existing timings are the recogniser's measurements of real speech;
        // flattening them to an even spread to accommodate a 0.1s nudge would
        // throw that away. Must run before the range is overwritten.
        rescaleWordTimings(in: segment, toStart: start, end: end)
        segment.startTime = start
        segment.endTime = end
        finishSegmentEdit()
    }

    private func applyText(_ text: String, to segment: CaptionSegment) {
        segment.text = text
        let words = text.split(separator: " ").map(String.init)
        segment.words = Self.evenlySpaced(words, from: segment.startTime, to: segment.endTime)
    }

    private func rescaleWordTimings(in segment: CaptionSegment, toStart start: Double, end: Double) {
        let existing = segment.words
        guard !existing.isEmpty else { return }

        let oldStart = segment.startTime
        let oldDuration = segment.endTime - oldStart
        guard oldDuration > 0 else {
            // Nothing to scale from. An even spread is the only information
            // left, and it is still better than leaving the words behind.
            segment.words = Self.evenlySpaced(existing.map(\.word), from: start, to: end)
            return
        }

        let factor = (end - start) / oldDuration
        segment.words = existing.map { word in
            WordTiming(
                word: word.word,
                startTime: start + (word.startTime - oldStart) * factor,
                endTime: start + (word.endTime - oldStart) * factor
            )
        }
    }

    private static func evenlySpaced(_ words: [String], from start: Double, to end: Double) -> [WordTiming] {
        guard !words.isEmpty else { return [] }
        let each = (end - start) / Double(words.count)
        return words.enumerated().map { index, word in
            WordTiming(
                word: word,
                startTime: start + Double(index) * each,
                endTime: start + Double(index + 1) * each
            )
        }
    }

    private func finishSegmentEdit() {
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

    /// Adopts `style` for the preview and records it on the project.
    ///
    /// Both the style picker and the Text Size slider come through here — the
    /// slider hands over a copy of the current style with a new `fontSize`. So
    /// the size has to be persisted alongside the name, or the slider only ever
    /// moves the preview.
    func selectStyle(_ style: CaptionStyle) {
        selectedStyle = style
        project.updateStyle(style.name, fontSize: Double(style.fontSize))
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

    /// Starts reporting playback time, replacing any previous registration.
    ///
    /// The view calls this from `.onAppear`, which fires again every time the
    /// editor comes back — after the export screen is dismissed, for instance.
    /// This used to overwrite `timeObserver` with a fresh token and drop the
    /// old one on the floor, so the previous observer kept firing 20 times a
    /// second with no way left to remove it, one more of them per visit.
    func setupTimeObserver() {
        guard let playbackClock else { return }
        teardownTimeObserver()

        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = playbackClock.addPeriodicObserver(every: interval) { [weak self] time in
            self?.currentPlaybackTime = CMTimeGetSeconds(time)
        }
    }

    /// Stops reporting playback time. Does nothing if it was not started.
    func teardownTimeObserver() {
        guard let timeObserver, let playbackClock else { return }
        playbackClock.removePeriodicObserver(timeObserver)
        self.timeObserver = nil
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
