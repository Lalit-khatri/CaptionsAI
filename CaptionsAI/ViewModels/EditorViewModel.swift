import AVFoundation
import AVKit
import SwiftUI

// MARK: - Transcription Budget

/// The shortest the editor will ever wait for a transcription, however brief
/// the clip. Startup, authorization and audio extraction all happen inside
/// this window.
let kMinimumTranscriptionBudget: TimeInterval = 90

/// How many times the clip's own length the editor is willing to wait.
///
/// Recognition normally runs at or faster than real time, so this is a
/// deliberately slack bound: it exists to end a run that has stopped making
/// progress at all, not to hurry a slow one along.
let kTranscriptionBudgetFactor: Double = 6

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

    /// Whether the project's video file could not be found when this editor
    /// opened. Decided once, in `init`, and not revisited — see the comment
    /// there for why a view must not ask the filesystem this question.
    private(set) var videoIsMissing = false
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

    /// The audio route the editor claims while it is on screen. Injected so
    /// tests can watch it being taken and handed back.
    private let audioSession: any AudioSessionControlling

    /// Overrides the computed transcription budget. Supplied by tests only, so
    /// that a test for "the editor stopped waiting" does not have to wait
    /// ninety seconds to make its point.
    private let injectedTranscriptionBudget: TimeInterval?

    /// How long the editor will wait for this project's transcription.
    var transcriptionBudget: TimeInterval {
        injectedTranscriptionBudget
            ?? Self.transcriptionBudget(forClipOf: project.videoDuration)
    }

    /// The time budget for a clip of `duration` seconds.
    static func transcriptionBudget(forClipOf duration: Double) -> TimeInterval {
        max(kMinimumTranscriptionBudget, duration * kTranscriptionBudgetFactor)
    }

    // MARK: - Init

    init(
        project: Project,
        speechRecognizer: any Transcribing = SpeechRecognizer(),
        playbackClock: (any PeriodicTimeObserving)? = nil,
        audioSession: any AudioSessionControlling = AVAudioSession.sharedInstance(),
        transcriptionBudget: TimeInterval? = nil
    ) {
        self.project = project
        self.speechRecognizer = speechRecognizer
        self.audioSession = audioSession
        injectedPlaybackClock = playbackClock
        injectedTranscriptionBudget = transcriptionBudget
        segments = project.sortedSegments
        selectedStyle = project.selectedStyle

        // Configure audio session for the video playback
        try? audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
        try? audioSession.setActive(true, options: [])

        if let url = project.videoURL {
            player = AVPlayer(url: url)
            observePlaybackEnd()
        } else {
            // Recorded here, once, rather than asked of the view. `videoURL`
            // is not a stored property — it calls VideoLibrary.resolve, which
            // hits the filesystem — so reading it from a `body` is a stat per
            // frame on the screen that is also decoding video.
            videoIsMissing = true
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

    // MARK: - Audio Session

    /// Hands the audio route back when the editor closes.
    ///
    /// Claiming a `.playback` session interrupts whatever else the phone was
    /// playing. Nothing used to release it, so the interruption outlived the
    /// screen: leave the editor and the user's music stayed stopped until the
    /// app was killed. `.notifyOthersOnDeactivation` is the part that tells
    /// the other app it may resume — releasing without it leaves the music
    /// paused just the same.
    func endPlaybackSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
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

    /// Whether a transcription has run to an end — captions, an error, or
    /// a refusal — in this editor. A cancelled run does not count: it was
    /// cut short, usually by the editor going off screen, and deserves
    /// another go when it comes back.
    private(set) var hasFinishedTranscription = false

    /// Transcribes on the editor's first appearance if there is nothing yet.
    ///
    /// The view used to check `segments.isEmpty` alone, from `.task`, which
    /// runs on every appearance. A user who deleted every caption on purpose
    /// and then looked at Export came back to a fresh transcript they had not
    /// asked for; a clip with no speech was re-transcribed, and the same
    /// error shown, on every return.
    @MainActor
    func transcribeIfNeeded() {
        guard segments.isEmpty, !hasFinishedTranscription, transcriptionTask == nil else { return }
        startTranscription()
    }

    @MainActor
    func generateCaptions() async {
        defer {
            if !Task.isCancelled { hasFinishedTranscription = true }
        }
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

            let budget = transcriptionBudget
            let newSegments = try await withDeadline(
                seconds: budget,
                throwing: { SpeechError.timedOut }
            ) { [speechRecognizer] in
                try await speechRecognizer.recognizeSpeech(from: videoURL)
            }

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
        let (validStart, validEnd) = validatedTiming(start: start, end: end)
        // Carry the measured timings to the new range first, so that a text
        // edit with the same number of words can keep them.
        rescaleWordTimings(in: segment, toStart: validStart, end: validEnd)
        segment.startTime = validStart
        segment.endTime = validEnd
        applyText(text, to: segment)
        reorderSegments()
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
        let (validStart, validEnd) = validatedTiming(start: start, end: end)
        rescaleWordTimings(in: segment, toStart: validStart, end: validEnd)
        segment.startTime = validStart
        segment.endTime = validEnd
        reorderSegments()
        finishSegmentEdit()
    }

    private func validatedTiming(start: Double, end: Double) -> (start: Double, end: Double) {
        let validStart = max(0, start)
        var validEnd = max(validStart, end)
        if project.videoDuration > 0 {
            if validStart > project.videoDuration {
                return (project.videoDuration, project.videoDuration)
            }
            validEnd = min(validEnd, project.videoDuration)
        }
        return (validStart, validEnd)
    }

    private func reorderSegments() {
        let sorted = project.segments.sorted {
            if $0.startTime != $1.startTime {
                return $0.startTime < $1.startTime
            }
            return $0.sortOrder < $1.sortOrder
        }
        for (index, segment) in sorted.enumerated() {
            segment.sortOrder = index
        }
    }

    private func applyText(_ text: String, to segment: CaptionSegment) {
        segment.text = text
        segment.words = Self.wordTimings(
            for: text,
            keeping: segment.words,
            from: segment.startTime,
            to: segment.endTime
        )
    }

    /// Word timings for `text` across `start...end`.
    ///
    /// When the word count is unchanged — fixing a misheard word, correcting
    /// case or punctuation, the common edit — the existing timings are kept
    /// and only the words swapped. They are the recogniser's measurements of
    /// real speech; every edit used to flatten them to an even spread, so
    /// correcting one typo put the highlight out of step with the voice for
    /// the whole caption. A different count leaves no way to say which word
    /// went where, so those are spread evenly.
    ///
    /// Words are split on any whitespace. Splitting on spaces alone turned a
    /// line break typed in the editor into part of a "word", so two words
    /// either side of it highlighted as one.
    static func wordTimings(
        for text: String,
        keeping existing: [WordTiming],
        from start: Double,
        to end: Double
    ) -> [WordTiming] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.count == existing.count else {
            return evenlySpaced(words, from: start, to: end)
        }
        return zip(existing, words).map { timing, word in
            WordTiming(word: word, startTime: timing.startTime, endTime: timing.endTime)
        }
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

    /// What a caption added by hand says until the user types over it.
    static let newCaptionText = "New caption"
    /// How long a caption added by hand lasts, where the video allows.
    static let newCaptionDuration: Double = 2

    /// Where a caption added at `time` goes.
    ///
    /// Pulled back from the end of the video rather than clipped by it: added
    /// at the last second, a clipped caption was zero seconds long and could
    /// never be seen. A video shorter than the default gets one caption over
    /// all of it. A duration of 0 means unknown, and nothing is clipped.
    static func newCaptionRange(at time: Double, videoDuration: Double) -> (start: Double, end: Double) {
        let start = max(0, time)
        guard videoDuration > 0 else { return (start, start + newCaptionDuration) }

        let latestStart = max(0, videoDuration - newCaptionDuration)
        let clampedStart = min(start, latestStart)
        return (clampedStart, min(clampedStart + newCaptionDuration, videoDuration))
    }

    /// Adds a caption at `time` and returns it, so the caller can open it
    /// for editing.
    ///
    /// Given evenly spaced word timings like any edited caption; with none,
    /// word-by-word styles showed it with nothing highlighted until the user
    /// happened to edit it.
    @discardableResult
    func addSegment(at time: Double, text: String = EditorViewModel.newCaptionText) -> CaptionSegment {
        let range = Self.newCaptionRange(at: time, videoDuration: project.videoDuration)
        let segment = CaptionSegment(
            startTime: range.start,
            endTime: range.end,
            text: text,
            sortOrder: segments.count
        )
        applyText(text, to: segment)
        project.addSegment(segment)
        reorderSegments()
        finishSegmentEdit()
        return segment
    }

    func deleteSegment(_ segment: CaptionSegment) {
        project.removeSegment(segment)
        reorderSegments()
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

    /// The size the Text Size slider shows and sets.
    ///
    /// Derived rather than stored. The editor used to hold the slider's value
    /// in its own `@State`, seeded once from the project — so picking a preset
    /// changed the caption but not the readout, which then disagreed with what
    /// was on screen, and the next nudge of the slider snapped the caption back
    /// to the stale number.
    var captionFontSize: CGFloat {
        get { selectedStyle.fontSize }
        set {
            var resized = selectedStyle
            resized.fontSize = newValue
            selectStyle(resized)
        }
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

    /// Plays if paused, pauses if playing. Does nothing without a video.
    func togglePlayPause() {
        guard let player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    /// Stops playback, whatever state it was in.
    ///
    /// Called when the editor goes off screen. Nothing used to pause the
    /// player then, so pushing Export or Preview while the video played left
    /// its audio running underneath the next screen — which was busy playing
    /// its own copy of the same clip.
    func pausePlayback() {
        player?.pause()
        isPlaying = false
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
