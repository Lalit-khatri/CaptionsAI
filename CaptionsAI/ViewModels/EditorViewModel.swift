import SwiftUI
import AVFoundation
import AVKit

// MARK: - EditorViewModel

/// Manages caption editing, style selection, and video playback.
@Observable
final class EditorViewModel {
    
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
    private var timeObserver: Any?
    
    // MARK: - Engine
    
    let speechRecognizer = SpeechRecognizer()
    
    // MARK: - Init
    
    init(project: Project) {
        self.project = project
        self.segments = project.sortedSegments
        self.selectedStyle = project.selectedStyle

        // Configure audio session for the video playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode:.moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        if let url = project.videoURL {
            self.player = AVPlayer(url: url)
        }
    }
    
    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
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
            let authorized = await SpeechRecognizer.requestAuthorization()
            guard authorized else {
                error = "Speech recognition not authorized"
                isProcessing = false
                return
            }
            
            let newSegments = try await speechRecognizer.recognizeSpeech(from: videoURL)
            
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
        project.modifiedAt = Date()
    }
    
    func updateSegmentTiming(_ segment: CaptionSegment, start: Double, end: Double) {
        segment.startTime = start
        segment.endTime = end
        project.modifiedAt = Date()
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
