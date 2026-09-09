import SwiftUI

// MARK: - TranscriptSheetView

/// Bottom sheet showing the full transcript as a scrollable list.
/// Presents the segment editor sheet internally so it appears on top.
struct TranscriptSheetView: View {
    let segments: [CaptionSegment]
    let currentPlaybackTime: Double
    let onSeek: (Double) -> Void
    let onSave: (CaptionSegment, String, Double, Double) -> Void
    let onDelete: (CaptionSegment) -> Void

    @State private var editingSegment: CaptionSegment?

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
                            ? Color(hex: "#7C3AED").opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            // Segment editor presented from within this sheet
            .sheet(item: $editingSegment) { segment in
                SegmentEditorSheet(
                    segment: segment,
                    onSave: { text, start, end in
                        onSave(segment, text, start, end)
                    }
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - Segment Editor Sheet

/// Editor for a single caption segment's text and timing.
struct SegmentEditorSheet: View {
    let segment: CaptionSegment
    let onSave: (String, Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var startTime: Double
    @State private var endTime: Double

    init(segment: CaptionSegment, onSave: @escaping (String, Double, Double) -> Void) {
        self.segment = segment
        self.onSave = onSave
        _text = State(initialValue: segment.text)
        _startTime = State(initialValue: segment.startTime)
        _endTime = State(initialValue: segment.endTime)
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
                        Stepper("", value: $startTime, in: 0 ... endTime, step: 0.1)
                            .labelsHidden()
                    }

                    HStack {
                        Text("End")
                        Spacer()
                        Text(String(format: "%.1fs", endTime))
                        Stepper("", value: $endTime, in: startTime ... 3600, step: 0.1)
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

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let segment: CaptionSegment
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Time range
            Text(segment.formattedTimeRange)
                .font(.caption.monospaced())
                .foregroundColor(isActive ? Color(hex: "#7C3AED") : .secondary)
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
