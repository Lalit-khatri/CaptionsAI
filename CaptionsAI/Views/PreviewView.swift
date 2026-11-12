import AVKit
import SwiftUI

// MARK: - PreviewView

/// Full-screen video preview with live caption overlay.
struct PreviewView: View {
    let project: Project
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    private var timeObserver: Any?

    init(project: Project) {
        self.project = project
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video with captions
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .overlay {
//              CaptionOverlay(
//                currentTime: currentTime,
//                segments: Binding(
//                  get: { project.segments },
//                  set: { _ in }
//                ),
//                style: project.selectedStyle,
//                yPosition: Binding(
//                  get: { 0 },
//                  set: { _ in /*  skip ntg to do **/ }
//                ),
//                onPositionChanged: { _ in
//                  // skip ntg to do.
//                }
//              )
                        }
                } else {
                    Color.black
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            // Playback controls
            VStack(spacing: 12) {
                // Timeline
                Slider(value: $currentTime, in: 0 ... max(duration, 1)) { editing in
                    if !editing {
                        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                    }
                }
                .tint(AppTheme.current.accent)

                // Time + Play/Pause
                HStack {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text(formatTime(currentTime) + " / " + formatTime(duration))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                NavigationLink(value: AppScreen.editor(project)) {
                    Text("Edit")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                        )
                }

                NavigationLink(value: AppScreen.export(project)) {
                    Text("Export")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: AppTheme.current.gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setupPlayer() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let url = project.videoURL else { return }
        let avPlayer = AVPlayer(url: url)
        player = avPlayer
        duration = project.videoDuration

        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
