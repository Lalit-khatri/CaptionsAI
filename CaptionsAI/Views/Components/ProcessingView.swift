import SwiftUI

// MARK: - ProcessingView

/// Loading overlay shown during speech recognition.
struct ProcessingView: View {
    let progress: Double
    let words: [String]
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
                Text("Analyzing Speech...")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                // Waveform animation
                waveformView
                    .frame(height: 60)
                    .padding(.horizontal, 40)

                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(
                            LinearGradient(
                                colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 40)

                    Text("Processing \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Live word feed
                if !words.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(words.suffix(8), id: \.self) { word in
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

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4)
                    .frame(height: animatingBars ? CGFloat.random(in: 10 ... 50) : 10)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3 ... 0.6))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05),
                        value: animatingBars
                    )
            }
        }
    }
}
