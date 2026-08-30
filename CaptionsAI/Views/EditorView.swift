import AVKit
import SwiftUI

// MARK: - EditorView

/// Main editing screen with full-screen video player and bottom action bar.
struct EditorView: View {
  let project: Project
  @State private var viewModel: EditorViewModel
  @State private var showStyleSheet = false
  @State private var showTranscriptSheet = false
  @State private var fontSize: CGFloat = 28
    
  init(project: Project) {
    self.project = project
    self._viewModel = State(initialValue: EditorViewModel(project: project))
    self._fontSize = State(initialValue: project.selectedStyle.fontSize)
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
          onCancel: { viewModel.isProcessing = false }
        )
      }
    }
    .navigationTitle("Edit")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.black, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .onAppear { viewModel.setupTimeObserver() }
    .task {
      if viewModel.segments.isEmpty {
        await viewModel.generateCaptions()
      }
    }
    // Style bottom sheet
    .sheet(isPresented: $showStyleSheet) {
      StyleSheetView(
        selectedStyle: Binding(
          get: { viewModel.selectedStyle },
          set: { viewModel.selectStyle($0) }
        ),
        fontSize: $fontSize,
        previewText: previewTextForStyle
      )
      .onChange(of: fontSize) { _, newSize in
        var updatedStyle = viewModel.selectedStyle
        updatedStyle.fontSize = newSize
        viewModel.selectStyle(updatedStyle)
      }
    }
    // Transcript bottom sheet
    .sheet(isPresented: $showTranscriptSheet) {
      TranscriptSheetView(
        segments: viewModel.segments,
        currentPlaybackTime: viewModel.currentPlaybackTime,
        onSeek: { time in
          viewModel.seekTo(time)
        },
        onSave: { segment, text, start, end in
          viewModel.updateSegmentText(segment, newText: text)
          viewModel.updateSegmentTiming(segment, start: start, end: end)
        },
        onDelete: { segment in
          viewModel.deleteSegment(segment)
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
    
  // MARK: - Preview Text for Style Cards
    
  /// Gets a short transcript snippet for style card preview
  private var previewTextForStyle: String {
    if let firstSegment = viewModel.segments.first {
      let words = firstSegment.text.split(separator: " ")
      let preview = words.prefix(4).joined(separator: " ")
      return preview.isEmpty ? "Hello World" : preview
    }
    return "Hello World"
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
              togglePlayPause()
            }
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
        togglePlayPause()
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
    
  // MARK: - Playback
    
  private func togglePlayPause() {
    guard let player = viewModel.player else { return }
        
    if viewModel.isPlaying {
      player.pause()
    } else {
      player.play()
    }
    viewModel.isPlaying.toggle()
  }
}
