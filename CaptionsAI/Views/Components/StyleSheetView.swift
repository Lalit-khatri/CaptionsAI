import SwiftUI

// MARK: - StyleSheetView

/// Bottom sheet for selecting caption styles and adjusting text size.
struct StyleSheetView: View {
    @Binding var selectedStyle: CaptionStyle
    @Binding var fontSize: CGFloat
    let previewText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title
            Text("Caption Style")
                .font(.headline)
                .foregroundColor(.white)

            // Style cards - horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CaptionStyle.presets) { style in
                        StylePreviewCard(
                            style: style,
                            isSelected: selectedStyle.name == style.name,
                            previewText: previewText
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedStyle = style
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Text Size Slider
            VStack(spacing: 8) {
                HStack {
                    Text("Text Size")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(fontSize))pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.white)
                }

                HStack(spacing: 12) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: $fontSize, in: 16 ... 48, step: 2)
                        .tint(Color(hex: "#7C3AED"))

                    Image(systemName: "textformat.size.larger")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Style Preview Card

/// Internal rather than private so `StylePreviewCardTests` can render it: the
/// point of the chip is that it looks like the style, which is only checkable
/// by drawing it.
struct StylePreviewCard: View {
    let style: CaptionStyle
    let isSelected: Bool
    let previewText: String

    private var words: [String] {
        let splitWords = previewText.split(separator: " ").map(String.init)
        let slice = Array(splitWords.prefix(3))
        let base = slice.isEmpty ? ["VIRAL", "CAPTIONS"] : slice
        return style.isUppercase ? base.map { $0.uppercased() } : base
    }

    var body: some View {
        VStack(spacing: 6) {
            // Preview box
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#111118"))
                    .frame(width: 104, height: 64)

                HStack(spacing: 3) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        let isHighlighted = style.wordByWordHighlight && (index == words.count - 1 || words.count == 1)
                        Text(word)
                            .font(style.font(size: 11))
                            .fontWeight(style.weight(highlighted: isHighlighted))
                            .foregroundColor(isHighlighted ? style.highlightColor.color : style.textColor.color)
                    }
                }
                .shadow(
                    color: style.shadowColor.color.opacity(style.shadowRadius > 0 ? 0.9 : 0),
                    radius: min(style.shadowRadius, 4)
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Group {
                        if style.backgroundOpacity > 0 {
                            RoundedRectangle(cornerRadius: style.cornerRadius > 0 ? 5 : 0)
                                .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                        }
                    }
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(hex: "#7C3AED") : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#7C3AED"))
                        .background(Circle().fill(Color.black))
                        .offset(x: 4, y: -4)
                }
            }

            // Style name
            Text(style.name)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundColor(isSelected ? Color(hex: "#A78BFA") : .secondary)
        }
    }
}
