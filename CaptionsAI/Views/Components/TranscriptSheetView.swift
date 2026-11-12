import SwiftUI

// MARK: - TranscriptSheetView

/// Bottom sheet showing the full transcript as a scrollable list.
/// Presents the segment editor sheet internally so it appears on top.
struct TranscriptSheetView: View {
    let segments: [CaptionSegment]
    let currentPlaybackTime: Double
    /// Length of the video, in seconds. Bounds the timing steppers.
    let videoDuration: Double
    let onSeek: (Double) -> Void
    let onSave: (CaptionSegment, String, Double, Double) -> Void
    let onDelete: (CaptionSegment) -> Void
    /// Adds a caption at the playhead and returns it.
    let onAdd: () -> CaptionSegment
    /// Runs transcription again. Nil when it cannot work (no video).
    var onTranscribe: (() -> Void)? = nil

    @State private var editingSegment: CaptionSegment?
    /// The caption Add Caption just created, until its editor is saved.
    @State private var unsavedNewSegment: CaptionSegment?

    static let addTitle = "Add Caption"
    static let addSymbol = "plus"
    static let emptyTitle = "No Captions"
    static let emptySymbol = "captions.bubble"
    static let emptyMessage = "Add a caption at the current point in the video."
    static let transcribeTitle = "Generate Captions"

    var body: some View {
        NavigationStack {
            List {
                ForEach(segments) { segment in
                    TranscriptRow(
                        segment: segment,
                        isActive: segment.isActive(at: currentPlaybackTime)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSeek(segment.startTime)
                        editingSegment = segment
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(segment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(
                        segment.isActive(at: currentPlaybackTime)
                            ? AppTheme.current.accent.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            // Delete every caption, or transcribe a clip with no speech, and
            // this sheet used to be an empty list with no way to add one.
            .overlay {
                if segments.isEmpty {
                    ContentUnavailableView {
                        Label(Self.emptyTitle, systemImage: Self.emptySymbol)
                    } description: {
                        Text(Self.emptyMessage)
                    } actions: {
                        // After a failed or cancelled run this was the only
                        // screen with no captions, and nothing on it could
                        // start another run short of leaving the project.
                        if let onTranscribe {
                            Button(Self.transcribeTitle) { onTranscribe() }
                                .buttonStyle(.borderedProminent)
                        }
                        Button(Self.addTitle) { addCaption() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .toolbar {
                // Leading: the trailing corner holds the feedback menu.
                ToolbarItem(placement: .topBarLeading) {
                    Button { addCaption() } label: {
                        Label(Self.addTitle, systemImage: Self.addSymbol)
                    }
                }
            }
            .navigationTitle("Transcript")
            .feedbackMenu()
            .navigationBarTitleDisplayMode(.inline)
            // Segment editor presented from within this sheet
            .sheet(item: $editingSegment, onDismiss: discardUnsavedNewSegment) { segment in
                SegmentEditorSheet(
                    segment: segment,
                    videoDuration: videoDuration,
                    onSave: { text, start, end in
                        if unsavedNewSegment === segment { unsavedNewSegment = nil }
                        onSave(segment, text, start, end)
                    }
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Adds the caption and opens it straight away, since the placeholder
    /// text is never what the user wants it to say.
    private func addCaption() {
        let segment = onAdd()
        unsavedNewSegment = segment
        editingSegment = segment
    }

    /// Add Caption followed by Cancel (or a swipe down) used to leave a
    /// "New caption" placeholder in the transcript, which then went out in
    /// the export. A new caption nobody saved is removed again.
    private func discardUnsavedNewSegment() {
        if let segment = unsavedNewSegment {
            unsavedNewSegment = nil
            onDelete(segment)
        }
    }
}

// MARK: - Segment Editor Sheet

/// Editor for a single caption segment's text and timing.
struct SegmentEditorSheet: View {
    let segment: CaptionSegment
    /// Length of the video, in seconds.
    let videoDuration: Double
    let onSave: (String, Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var startTime: Double
    @State private var endTime: Double

    init(segment: CaptionSegment, videoDuration: Double, onSave: @escaping (String, Double, Double) -> Void) {
        self.segment = segment
        self.videoDuration = videoDuration
        self.onSave = onSave
        _text = State(initialValue: segment.text)
        _startTime = State(initialValue: segment.startTime)
        _endTime = State(initialValue: segment.endTime)
    }

    /// The largest end time the stepper offers.
    ///
    /// This used to be the literal `3600`. Past the one-hour mark a caption's
    /// start time is greater than that, and `startTime ... 3600` is not a
    /// range — forming it traps, so opening any caption after 60:00 in a
    /// longer video killed the app. The literal was wrong in the other
    /// direction too: in a 90-second video it let a caption be stretched to an
    /// hour, far past the last frame.
    ///
    /// `end` is included so the value already on screen is always inside the
    /// range, even for a segment that somehow sits past the end of its video.
    /// Save is offered only for text with something in it. The editor would
    /// ignore blank text anyway; a live Save that does nothing is worse.
    static func canSave(text: String) -> Bool {
        EditorViewModel.captionText(from: text) != nil
    }

    static func latestEnd(start: Double, end: Double, videoDuration: Double) -> Double {
        max(videoDuration, max(start, end))
    }

    /// The smallest end time the stepper offers: one step after the start,
    /// so a caption cannot be shrunk to nothing. Never above `latestEnd`, or
    /// the range would not form.
    static func earliestEnd(start: Double, end: Double, videoDuration: Double) -> Double {
        min(start + kMinimumCaptionLength, latestEnd(start: start, end: end, videoDuration: videoDuration))
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
                        Stepper("", value: $startTime, in: 0 ... max(0, endTime - kMinimumCaptionLength), step: 0.1)
                            .labelsHidden()
                    }

                    HStack {
                        Text("End")
                        Spacer()
                        Text(String(format: "%.1fs", endTime))
                        Stepper(
                            "",
                            value: $endTime,
                            in: Self.earliestEnd(start: startTime, end: endTime, videoDuration: videoDuration)
                                ... Self.latestEnd(start: startTime, end: endTime, videoDuration: videoDuration),
                            step: 0.1
                        )
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
                    .disabled(!Self.canSave(text: text))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let segment: CaptionSegment
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Time range
            Text(segment.formattedTimeRange)
                .font(.caption.monospaced())
                .foregroundColor(isActive ? AppTheme.current.accent : .secondary)
                .frame(width: 90, alignment: .leading)

            // Caption text
            Text(segment.text)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer()

            // Edit indicator
            Image(systemName: "pencil")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 6)
    }
}
