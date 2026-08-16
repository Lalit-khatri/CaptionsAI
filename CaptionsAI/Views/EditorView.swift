import SwiftUI
import AVKit

// MARK: - EditorView

/// Main editing screen with video player, style picker, and caption list.
struct EditorView: View {
    let project: Project
    @State private var viewModel: EditorViewModel
    @State private var showSegmentEditor = false
    @State private var editingSegment: CaptionSegment?
    
    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: EditorViewModel(project: project))
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Video player with caption overlay
                videoPlayerSection
                
                // Style picker
                StylePickerView(
                    selectedStyle: Binding(
                        get: { viewModel.selectedStyle },
                        set: { viewModel.selectStyle($0) }
                    )
                )
                .padding(.vertical, 12)
                
                // Caption segments list
                captionsList
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
        .navigationTitle("Edit Captions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { viewModel.setupTimeObserver() }
        .task {
            if viewModel.segments.isEmpty {
                await viewModel.generateCaptions()
            }
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditorSheet(
                segment: segment,
                onSave: { text, start, end in
                    viewModel.updateSegmentText(segment, newText: text)
                    viewModel.updateSegmentTiming(segment, start: start, end: end)
                }
            )
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayerSection: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        CaptionOverlay(
                            currentTime: viewModel.currentPlaybackTime,
                            segments: viewModel.segments,
                            style: viewModel.selectedStyle
                        )
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Captions List
    
    private var captionsList: some View {
        List {
            ForEach(viewModel.segments) { segment in
                SegmentRow(
                    segment: segment,
                    isActive: segment.isActive(at: viewModel.currentPlaybackTime)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editingSegment = segment
                    viewModel.seekTo(segment.startTime)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteSegment(segment)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                viewModel.addSegment(at: viewModel.currentPlaybackTime)
            } label: {
                Label("Add", systemImage: "plus")
            }
            
            Spacer()
            
            Button {
                Task { await viewModel.generateCaptions() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            
            Spacer()
            
            NavigationLink(value: AppScreen.preview(project)) {
                Label("Preview", systemImage: "play.fill")
            }
            
            Spacer()
            
            NavigationLink(value: AppScreen.export(project)) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Segment Row

private struct SegmentRow: View {
    let segment: CaptionSegment
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(segment.formattedTimeRange)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text(segment.text)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            Image(systemName: "pencil")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color(hex: "#7C3AED").opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - Segment Editor Sheet

private struct SegmentEditorSheet: View {
    let segment: CaptionSegment
    let onSave: (String, Double, Double) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var startTime: Double
    @State private var endTime: Double
    
    init(segment: CaptionSegment, onSave: @escaping (String, Double, Double) -> Void) {
        self.segment = segment
        self.onSave = onSave
        self._text = State(initialValue: segment.text)
        self._startTime = State(initialValue: segment.startTime)
        self._endTime = State(initialValue: segment.endTime)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Caption Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                }
                
                Section("Timing") {
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(String(format: "%.1fs", startTime))
                        Stepper("", value: $startTime, in: 0...endTime, step: 0.1)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("End")
                        Spacer()
                        Text(String(format: "%.1fs", endTime))
                        Stepper("", value: $endTime, in: startTime...3600, step: 0.1)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text, startTime, endTime)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
