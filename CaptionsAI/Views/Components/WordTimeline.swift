import SwiftUI

// MARK: - WordTimeline

/// Horizontal word-level timeline for precise timing adjustments.
struct WordTimeline: View {
    let segment: CaptionSegment
    @Binding var selectedWord: WordTiming?
    let onTimingChange: (WordTiming, Double, Double) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Word blocks
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(segment.words) { word in
                        WordBlock(
                            word: word,
                            isSelected: selectedWord?.id == word.id
                        )
                        .onTapGesture {
                            withAnimation {
                                selectedWord = word
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Timing controls for selected word
            if let word = selectedWord {
                VStack(spacing: 12) {
                    // Word text
                    HStack {
                        Text("Word")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(word.word)
                            .font(.subheadline.bold())
                    }

                    Divider()

                    // Start time
                    HStack {
                        Text("Start")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2fs", word.startTime))
                            .font(.subheadline.monospaced())

                        HStack(spacing: 0) {
                            Button {
                                let newStart = max(0, word.startTime - 0.05)
                                onTimingChange(word, newStart, word.endTime)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 32, height: 28)
                            }

                            Divider().frame(height: 20)

                            Button {
                                let newStart = min(word.endTime - 0.05, word.startTime + 0.05)
                                onTimingChange(word, newStart, word.endTime)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 32, height: 28)
                            }
                        }
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // End time
                    HStack {
                        Text("End")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2fs", word.endTime))
                            .font(.subheadline.monospaced())

                        HStack(spacing: 0) {
                            Button {
                                let newEnd = max(word.startTime + 0.05, word.endTime - 0.05)
                                onTimingChange(word, word.startTime, newEnd)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 32, height: 28)
                            }

                            Divider().frame(height: 20)

                            Button {
                                onTimingChange(word, word.startTime, word.endTime + 0.05)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 32, height: 28)
                            }
                        }
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Word Block

private struct WordBlock: View {
    let word: WordTiming
    let isSelected: Bool

    var body: some View {
        Text(word.word)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(hex: "#7C3AED") : Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color(hex: "#7C3AED") : .clear, lineWidth: 1.5)
            )
    }
}
