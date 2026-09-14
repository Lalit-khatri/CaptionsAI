import SwiftUI

/// The "Share Video" and "Done" pair at the bottom of the export-completion
/// screen.
///
/// Lifted out of `ExportView.completedView` unchanged, for two reasons. It is
/// the only part of that screen a test can measure — the labels are static
/// functions the body itself calls, so a measurement is of the shipping
/// control and not of a copy of it. And it is the block that has to become
/// `safeAreaInset` content, which needs it to be a view of its own.
struct ExportCompletionFooter: View {
    let onShare: () -> Void
    let onDone: () -> Void

    static let buttonSpacing: CGFloat = 12
    static let bottomPadding: CGFloat = 24

    /// The primary control. The body calls this; so does the test that
    /// measures it.
    @ViewBuilder
    static func shareLabel() -> some View {
        Label("Share Video", systemImage: "square.and.arrow.up")
            .font(.headline)
            // At the largest accessibility text size this wrapped to three
            // lines and the footer alone took 281pt of an iPhone SE's 603pt.
            // One line that scales down gives that height back to the content.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    static func doneLabel() -> some View {
        Text("Done")
            .font(.subheadline.bold())
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ExportCompletionLayout.doneVerticalPadding)
    }

    var body: some View {
        VStack(spacing: Self.buttonSpacing) {
            Button(action: onShare) { Self.shareLabel() }
            Button(action: onDone) { Self.doneLabel() }
        }
        .padding(.bottom, Self.bottomPadding)
    }
}
