import SwiftUI

// MARK: - CaptionDragHintView

/// Visual hint shown on first use to teach users they can drag captions vertically.
struct CaptionDragHintView: View {
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.up.and.down")
        .font(.callout.bold())
      Text("Drag to move")
        .font(.callout.bold())
    }
    .foregroundColor(.white.opacity(0.9))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
    .clipShape(Capsule())
    .transition(.opacity.combined(with: .scale(scale: 0.8)))
  }
}

#Preview {
  ZStack {
    Color.black
    CaptionDragHintView()
  }
}
