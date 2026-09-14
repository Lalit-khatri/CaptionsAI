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

    /// The chip is exactly this size, whatever it is asked to draw.
    ///
    /// It used to be 104x64 with the frame on the plate — a *sibling* of the
    /// text inside the ZStack, which constrains the plate and nothing else. In
    /// a horizontal `ScrollView`, which proposes unbounded width, the text took
    /// its full single-line ideal width and the chip grew with the sample. That
    /// is also why it could only ever show three words: there was no width for
    /// `lineLimit` to wrap against, so wrapping never happened.
    ///
    /// 150 is chosen so two chips and a peek of a third fit a 375pt phone. The
    /// peek is what tells the user the row scrolls.
    static let plateWidth: CGFloat = 150
    static let plateHeight: CGFloat = 104

    /// Breathing room between the sample and the edge of the plate.
    private static let textInset: CGFloat = 10

    /// Enough of a sentence to judge a style by. Three words was too few to
    /// show what wrapping, weight and highlight do to a real caption.
    static let maximumSampleWords = 6

    /// The words the chip draws, in the style's own casing.
    ///
    /// A pure function of the sample so the rule can be pinned without
    /// rendering anything.
    static func sampleWords(from text: String, isUppercase: Bool) -> [String] {
        let split = text.split(separator: " ").map(String.init)
        let base = split.isEmpty ? ["VIRAL", "CAPTIONS"] : Array(split.prefix(maximumSampleWords))
        return isUppercase ? base.map { $0.uppercased() } : base
    }

    private var words: [String] {
        Self.sampleWords(from: previewText, isUppercase: style.isUppercase)
    }

    /// The sample as one concatenated `Text` rather than an `HStack` of them.
    ///
    /// An `HStack` cannot wrap — it lays its children out on one line and asks
    /// each for its ideal width. A single `Text` built by concatenation keeps
    /// the per-word colour and weight while letting the text engine break the
    /// line, which is the whole point of giving the chip a fixed width.
    private var sample: Text {
        words.enumerated().reduce(Text("")) { accumulated, entry in
            let (index, word) = entry
            let isHighlighted = style.wordByWordHighlight && (index == words.count - 1 || words.count == 1)
            let spacer = index == words.count - 1 ? "" : " "

            return accumulated + Text(word + spacer)
                .font(style.font(size: 13))
                .fontWeight(style.weight(highlighted: isHighlighted))
                .foregroundColor(isHighlighted ? style.highlightColor.color : style.textColor.color)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Preview box
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#111118"))
                    .frame(width: Self.plateWidth, height: Self.plateHeight)

                sample
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(width: Self.plateWidth - Self.textInset * 2)
                    .shadow(
                        color: style.shadowColor.color.opacity(style.shadowRadius > 0 ? 0.9 : 0),
                        radius: min(style.shadowRadius, 4)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Group {
                            if style.backgroundOpacity > 0 {
                                RoundedRectangle(cornerRadius: style.cornerRadius > 0 ? 6 : 0)
                                    .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                            }
                        }
                    )
            }
            .frame(width: Self.plateWidth, height: Self.plateHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
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
