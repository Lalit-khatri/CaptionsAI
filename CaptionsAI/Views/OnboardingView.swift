import SwiftUI

// MARK: - OnboardingView

/// First-launch welcome screen with feature highlights.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#1A1040"), Color(hex: "#0F1B3D")],
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
                            colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
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
                    FeatureRow(icon: "sparkles", text: "10+ professional caption styles")
                    FeatureRow(icon: "lock.shield", text: "100% offline — your videos stay private")
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
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
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
                .foregroundColor(Color(hex: "#7C3AED"))
                .frame(width: 32)
            
            Text(text)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}
