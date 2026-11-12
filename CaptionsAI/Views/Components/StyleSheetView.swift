import AVFoundation
import SwiftUI

// MARK: - StyleSheetView

/// Bottom sheet for selecting caption styles and adjusting text size.
struct StyleSheetView: View {
    @Binding var selectedStyle: CaptionStyle
    @Binding var fontSize: CGFloat
    let previewText: String
    /// The project's video. Its frame at ``frameTime`` goes behind every chip,
    /// so each style is judged over the user's own footage rather than a
    /// black plate. `nil`, or a file that will not decode, keeps the plate.
    var videoURL: URL?
    /// Where the editor's playhead is, in seconds.
    var frameTime: Double = 0
    @Environment(\.dismiss) private var dismiss
    /// The frame behind the chips, once it has been read.
    @State private var backdrop: UIImage?
    /// The tab showing. `nil` is All, which is where the sheet opens.
    @State private var category: StyleCategory?

    /// Where the sheet sits before anyone drags it. Tall enough for the chip
    /// row and the Text Size slider together.
    static let restingHeight: CGFloat = 380

    /// A single fixed detent is a hard cap — there is no gesture that can grow
    /// a sheet with nowhere to grow to. At the largest accessibility text sizes
    /// that pushed the Text Size slider below the fold and left it unreachable,
    /// which is a particularly unkind thing to do to the control that exists to
    /// make text bigger.
    static let detents: Set<PresentationDetent> = [.height(restingHeight), .large]

    /// What the Text Size slider offers. The floor used to be 16pt, which
    /// was too large for long lines on a small or busy frame; 4pt lets a user
    /// tuck captions into a corner.
    static let fontSizeRange: ClosedRange<CGFloat> = 4 ... 48
    static let fontSizeStep: CGFloat = 2

    /// Space above the title. At 8pt the title sat about 3pt under the
    /// grabber and read as touching it.
    static let titleTopPadding: CGFloat = 20

    /// Space between the sheet's edges and the tabs, the first and last chip,
    /// and the slider. One value, so the three line up down the left edge.
    static let edgeInset: CGFloat = 20

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Caption Style")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
                .padding(.top, Self.titleTopPadding)

            categoryTabs

            // Style cards - horizontal scroll
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleStyles) { style in
                            StylePreviewCard(
                                style: style,
                                isSelected: selectedStyle.name == style.name,
                                previewText: previewText,
                                backdrop: backdrop
                            )
                            .id(style.name)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedStyle = style
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Self.edgeInset)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: category) { scroll(proxy) }
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

                    Slider(value: $fontSize, in: Self.fontSizeRange, step: Self.fontSizeStep)
                        .tint(AppTheme.current.accent)

                    Image(systemName: "textformat.size.larger")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, Self.edgeInset)

            Spacer()
        }
        .task { backdrop = await Self.backdropFrame(from: videoURL, at: frameTime) }
        .presentationDetents(Self.detents)
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Scrolling to the Selection

    /// The styles in the showing tab.
    private var visibleStyles: [CaptionStyle] { StyleCategory.styles(in: category) }

    /// The chip the row should centre on: the selected style when the showing
    /// tab has it, otherwise the tab's first chip.
    ///
    /// A pure function of the selection and the list, so the rule can be
    /// pinned without a scroll view. Without it the sheet always opened at
    /// Hormozi, and anyone using a style past the second chip had to hunt
    /// for it to see which one was on.
    ///
    /// Falling back to the first chip matters on a tab change: the row keeps
    /// its old offset otherwise, which in the new tab lands on whichever chip
    /// happens to be there. That one is centred too, not leading-aligned:
    /// the row cannot scroll before its start, so centring the first chip
    /// comes to rest at the start with the edge inset intact, where a
    /// leading anchor pulled the chip flush against the sheet's edge.
    static func scrollTarget(selected: String, among styles: [CaptionStyle]) -> String? {
        if styles.contains(where: { $0.name == selected }) {
            return selected
        }
        return styles.first?.name
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = Self.scrollTarget(selected: selectedStyle.name, among: visibleStyles) else { return }
        proxy.scrollTo(target, anchor: .center)
    }

    // MARK: - Backdrop

    /// Big enough to stay sharp on a 3x screen at the chip's size, and no
    /// bigger: the frame is decoded once and shared by all thirty chips.
    static let backdropMaximumSize = CGSize(width: 480, height: 480)

    /// One frame of the video, upright, at `seconds` — or the first frame if
    /// that time cannot be read (past the end, say). `nil` when there is no
    /// video or it will not decode, which leaves the chips on their plate.
    static func backdropFrame(from url: URL?, at seconds: Double) async -> UIImage? {
        guard let url else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = backdropMaximumSize
        let requested = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        for time in [requested, .zero] {
            if let (image, _) = try? await generator.image(at: time) {
                return UIImage(cgImage: image)
            }
        }
        return nil
    }

    // MARK: - Category Tabs

    static let allTitle = "All"

    /// All, then one tab per category. Thirty styles in one row is a lot
    /// of scrolling to find the kind of look you are after.
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tab(Self.allTitle, for: nil)
                ForEach(StyleCategory.allCases) { category in
                    tab(category.title, for: category)
                }
            }
            .padding(.horizontal, Self.edgeInset)
        }
    }

    private func tab(_ title: String, for tabCategory: StyleCategory?) -> some View {
        let isSelected = category == tabCategory
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { category = tabCategory }
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? AppTheme.current.onAccent : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? AppTheme.current.accent : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    /// A frame of the user's video to draw the sample over. `nil` keeps the
    /// plain plate.
    var backdrop: UIImage?

    /// Darkens the backdrop so a white or pale style still reads on a bright
    /// frame. Light enough that the footage is still recognisable.
    static let backdropDim: Double = 0.35

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

    /// At 104 the resting sheet left a band of about 120pt empty under the
    /// Text Size slider. 160 spends most of it on the one thing in the sheet
    /// worth looking at, and still leaves the slider clear of the sheet's
    /// bottom edge at the resting height.
    static let plateHeight: CGFloat = 160

    /// Breathing room between the sample and the edge of the plate.
    private static let textInset: CGFloat = 10

    /// Enough of a sentence to judge a style by. Three words was too few to
    /// show what wrapping, weight and highlight do to a real caption.
    static let maximumSampleWords = 6

    /// Drawn when there is no transcript yet. `EditorView` uses the same
    /// string, so the chip cannot show one sentence before transcription and a
    /// different one when handed an empty segment.
    static let fallbackSample = "Check out this caption on video"

    /// The words the chip draws, in the style's own casing.
    ///
    /// A pure function of the sample so the rule can be pinned without
    /// rendering anything.
    static func sampleWords(from text: String, isUppercase: Bool) -> [String] {
        let split = text.split(separator: " ").map(String.init)
        let source = split.isEmpty ? fallbackSample.split(separator: " ").map(String.init) : split
        let base = Array(source.prefix(maximumSampleWords))
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
        // Read once. `words` is computed, and the closure below asks for its
        // count on every word, so each chip re-split its sample once per
        // word on every redraw of the style sheet.
        let words = self.words
        return words.enumerated().reduce(Text("")) { accumulated, entry in
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

                if let backdrop {
                    // Fill, then clip: a portrait frame must crop to the chip,
                    // not stretch it.
                    Image(uiImage: backdrop)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.plateWidth, height: Self.plateHeight)
                        .clipped()
                        .overlay(Color.black.opacity(Self.backdropDim))
                        .accessibilityHidden(true)
                }

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
                    .stroke(isSelected ? AppTheme.current.accent : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.current.accent)
                        .background(Circle().fill(Color.black))
                        // Inside the corner. Hanging 4pt outside it, the
                        // badge was cut off by the edge of the row.
                        .padding(5)
                }
            }

            // Style name
            Text(style.name)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundColor(isSelected ? AppTheme.current.accentText : .secondary)
        }
        // The chip is a swatch, not body copy, and it has to keep the height
        // of the row it scrolls in. Measured with this line removed (and the
        // plate 104pt tall), the card grew from 124pt to 158pt at
        // accessibility5 — for every preset, not
        // only the six that name a real typeface, because the style-name label
        // scales too. (Inside the plate there is a second, smaller effect:
        // `Font.custom(_:size:)` scales with the text size and
        // `Font.system(size:)` does not, so the two groups would diverge.)
        //
        // The captions themselves are drawn by the renderer and are unaffected
        // either way; the Text Size slider below is how caption size is meant
        // to be changed.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}
