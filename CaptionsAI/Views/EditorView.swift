import AVKit
import SwiftUI

// MARK: - EditorView

/// Main editing screen with full-screen video player and bottom action bar.
struct EditorView: View {
    let project: Project
    @State private var viewModel: EditorViewModel
    @State private var showStyleSheet = false
    @State private var showTranscriptSheet = false

    init(project: Project) {
        self.project = project
        _viewModel = State(initialValue: EditorViewModel(project: project))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video player fills all available space
                videoPlayerSection

                // Bottom action bar
                actionBar
            }

            // Processing overlay
            if viewModel.isProcessing {
                ProcessingView(
                    progress: viewModel.speechRecognizer.progress,
                    words: viewModel.speechRecognizer.partialResults,
                    preparation: viewModel.speechRecognizer.preparation,
                    onCancel: { viewModel.cancelTranscription() }
                )
            }
        }
        .navigationTitle("Edit")
        .feedbackMenu()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { viewModel.setupTimeObserver() }
        .task {
            viewModel.transcribeIfNeeded()
        }
        // `.task` used to own the transcription and cancel it on disappear.
        // The view model owns it now, so the teardown has to be explicit.
        .onDisappear {
            viewModel.pausePlayback()
            viewModel.cancelTranscription()
            viewModel.teardownTimeObserver()
            viewModel.endPlaybackSession()
        }
        // Style bottom sheet
        .sheet(isPresented: $showStyleSheet) {
            StyleSheetView(
                selectedStyle: Binding(
                    get: { viewModel.selectedStyle },
                    set: { viewModel.selectStyle($0) }
                ),
                fontSize: Binding(
                    get: { viewModel.captionFontSize },
                    set: { viewModel.captionFontSize = $0 }
                ),
                previewText: previewTextForStyle,
                videoURL: project.videoURL,
                frameTime: viewModel.currentPlaybackTime
            )
        }
        // Transcript bottom sheet
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptSheetView(
                segments: viewModel.segments,
                currentPlaybackTime: viewModel.currentPlaybackTime,
                videoDuration: project.videoDuration,
                onSeek: { time in
                    viewModel.seekTo(time)
                },
                onSave: { segment, text, start, end in
                    viewModel.updateSegment(segment, text: text, start: start, end: end)
                },
                onDelete: { segment in
                    viewModel.deleteSegment(segment)
                },
                onAdd: {
                    viewModel.addSegment(at: viewModel.currentPlaybackTime)
                }
            )
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: {
                if !$0 {
                    viewModel.error = nil
                }
            }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Export Availability

    /// Whether Export should be offered.
    ///
    /// `ExportView`'s own button does `guard let videoURL = project.videoURL
    /// else { return }`, so with no video the user taps a live-looking control
    /// and nothing happens at all — and then taps it again. Better to say no
    /// up front.
    static func exportIsAvailable(videoIsMissing: Bool) -> Bool {
        !videoIsMissing
    }

    // MARK: - Preview Text for Style Cards

    /// What the style chips are asked to draw when there is nothing to quote
    /// from the video yet — the chips are visible before transcription runs.
    ///
    /// One string, shared with the chip, which used to carry a second and
    /// different literal of its own for the empty case. Which of the two a user
    /// saw was an accident of timing.
    static let fallbackPreviewText = StylePreviewCard.fallbackSample

    /// The sample the style chips draw, taken from the transcript.
    ///
    /// Reads across segments rather than from the first one alone: a
    /// transcript's first segment is frequently one or two words, and a chip
    /// showing a single word shows nothing about a style — no wrap, no rhythm,
    /// and with word-by-word highlighting the entire sample lights up.
    static func previewText(segmentTexts: [String]) -> String {
        var words: [String] = []

        for text in segmentTexts {
            words += text.split(separator: " ").map(String.init)
            if words.count >= StylePreviewCard.maximumSampleWords { break }
        }

        let preview = words.prefix(StylePreviewCard.maximumSampleWords).joined(separator: " ")
        return preview.isEmpty ? fallbackPreviewText : preview
    }

    private var previewTextForStyle: String {
        Self.previewText(segmentTexts: viewModel.segments.map(\.text))
    }

    // MARK: - Video Player (fills available space)

    private var videoPlayerSection: some View {
        GeometryReader { _ in
            ZStack {
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .overlay {
                            CaptionOverlay(
                                viewModel: viewModel,
                                currentTime: viewModel.currentPlaybackTime,
                                yPosition: Binding(
                                    get: { viewModel.captionYPosition },
                                    set: { viewModel.captionYPosition = $0 }
                                ),
                                onPositionChanged: { newY in
                                    viewModel.captionYPosition = newY
                                }
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.togglePlayPause()
                        }
                } else if viewModel.videoIsMissing {
                    MissingVideoView()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            // Style button
            actionButton(icon: "paintbrush.fill", label: "Style") {
                showStyleSheet = true
            }

            // Transcript button
            actionButton(icon: "text.alignleft", label: "Transcript") {
                showTranscriptSheet = true
            }

            // Play/Pause button (larger, centered)
            Button {
                viewModel.togglePlayPause()
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#7C3AED"))
                            .frame(width: 48, height: 48)

                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }

                    Text(viewModel.isPlaying ? "Pause" : "Play")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            // Export button
            NavigationLink(value: AppScreen.export(project)) {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)

                    Text("Export")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
            }
            // Export's own button guards on the URL and silently returns, so
            // without this the user presses a live-looking control and nothing
            // whatsoever happens. Dimmed as well as disabled, because a
            // disabled control that still looks enabled is the same bug.
            .disabled(!Self.exportIsAvailable(videoIsMissing: viewModel.videoIsMissing))
            .opacity(Self.exportIsAvailable(videoIsMissing: viewModel.videoIsMissing) ? 1 : 0.35)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Action Button Helper

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)

                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
        }
    }
}
