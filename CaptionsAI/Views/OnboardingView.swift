import SwiftUI

// MARK: - OnboardingView

/// First-launch welcome screen with feature highlights.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: AppTheme.current.backdrop,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppTheme.current.vividGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 8)

                // Title
                VStack(spacing: 8) {
                    Text("CaptionsAI")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)

                    Text("AI Captions in Seconds")
                        .font(.title3)
                        .foregroundColor(.gray)
                }

                // Feature list
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "film", text: "Import any video")
                    FeatureRow(icon: "sparkles", text: "\(CaptionStyle.presets.count) professional caption styles")
                    FeatureRow(icon: "lock.shield", text: "On-device captions where supported")
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)

                Spacer()

                // CTA Button
                Button {
                    withAnimation {
                        appState.hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(AppTheme.current.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: AppTheme.current.gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)

                Text("No account needed")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppTheme.current.accent)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}
