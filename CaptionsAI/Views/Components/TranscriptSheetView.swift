import SwiftUI

// MARK: - TranscriptSheetView

/// Bottom sheet showing the full transcript as a scrollable list.
struct TranscriptSheetView: View {
    let segments: [CaptionSegment]
    let currentPlaybackTime: Double
    let onSeek: (Double) -> Void
    let onEdit: (CaptionSegment) -> Void
    let onDelete: (CaptionSegment) -> Void
    
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
                        onEdit(segment)
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
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
