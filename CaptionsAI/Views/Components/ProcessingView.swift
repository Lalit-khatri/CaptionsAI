import SwiftUI

// MARK: - ProcessingView

/// Loading overlay shown during speech recognition.
struct ProcessingView: View {
    let progress: Double
    let words: [String]
    /// Set while the recogniser gets its model ready, before any speech is
    /// analysed. A first Kannada video spends most of its wait here, and a
    /// screen that said "Analyzing Speech" at 0% through a 466 MB download
    /// would look stuck.
    var preparation: TranscriptionPreparation? = nil
    let onCancel: () -> Void

    @State private var animatingBars = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Title
                Text(Self.title(for: preparation))
                    .font(.title2.bold())
                    .foregroundColor(.white)

                // Waveform animation
                waveformView
                    .frame(height: 60)
                    .padding(.horizontal, 40)

                // Progress bar
                VStack(spacing: 8) {
                    progressBar
                        .tint(
                            LinearGradient(
                                colors: AppTheme.current.vividGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 40)

                    Text(Self.status(progress: progress, preparation: preparation))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Live word feed
                if !words.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(words.suffix(8).enumerated()), id: \.offset) { _, word in
                                Text(word)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Text("...")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding(.horizontal, 40)
                    }
                }

                Spacer()

                // Cancel button
                Button("Cancel", action: onCancel)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 48)
            }
        }
        .onAppear { animatingBars = true }
    }

    // MARK: - Copy

    static func title(for preparation: TranscriptionPreparation?) -> String {
        switch preparation {
        case .downloading: return "Downloading Speech Model..."
        case .loading: return "Preparing Speech Model..."
        case nil: return "Analyzing Speech..."
        }
    }

    static func status(progress: Double, preparation: TranscriptionPreparation?) -> String {
        switch preparation {
        case let .downloading(fraction): return "Downloading \(Int(fraction * 100))%"
        case .loading: return "Only slow the first time"
        case nil: return "Processing \(Int(progress * 100))%"
        }
    }

    // MARK: - Progress Bar

    /// Download progress while downloading, an indeterminate bar while the
    /// model loads (Core ML gives no progress for that), and the
    /// recogniser's own progress after.
    @ViewBuilder
    private var progressBar: some View {
        switch preparation {
        case let .downloading(fraction):
            ProgressView(value: fraction)
        case .loading:
            ProgressView(value: nil as Double?)
                .progressViewStyle(.linear)
        case nil:
            ProgressView(value: progress)
        }
    }

    // MARK: - Waveform

    /// Precomputed bar heights for the 20 waveform bars so that SwiftUI's
    /// `body` evaluation on every progress update does not re-roll random heights
    /// and reset the running animations.
    static let barHeights: [CGFloat] = [
        18, 32, 45, 28, 48, 22, 38, 50, 30, 42,
        20, 35, 48, 26, 44, 18, 36, 50, 24, 40
    ]

    /// Precomputed animation durations for the 20 waveform bars.
    static let barDurations: [Double] = [
        0.45, 0.35, 0.55, 0.40, 0.50, 0.38, 0.48, 0.52, 0.42, 0.36,
        0.46, 0.34, 0.54, 0.41, 0.49, 0.39, 0.47, 0.53, 0.43, 0.37
    ]

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: AppTheme.current.vividGradient,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4)
                    .frame(height: animatingBars ? Self.barHeights[index % Self.barHeights.count] : 10)
                    .animation(
                        .easeInOut(duration: Self.barDurations[index % Self.barDurations.count])
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05),
                        value: animatingBars
                    )
            }
        }
    }
}
