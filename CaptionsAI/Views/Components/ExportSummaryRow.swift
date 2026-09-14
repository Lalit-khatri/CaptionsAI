import SwiftUI

/// The "Format / Quality / Duration / Style" card under the success thumbnail
/// on the export-completion screen.
///
/// Lifted out of `ExportView.completedView` unchanged. It takes four plain
/// strings rather than reading a view model, so a test can render it: the
/// columns are the part of that screen whose width behaviour is in question,
/// and there is no way to put the screen itself in front of `ImageRenderer`.
struct ExportSummaryRow: View {
    let format: String
    let quality: String
    let duration: String
    let style: String

    static let cornerRadius: CGFloat = 12
    static let columnSpacing: CGFloat = 16
    static let dividerHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            detail(title: "Format", value: format)
            Divider().frame(height: Self.dividerHeight)
            detail(title: "Quality", value: quality)
            Divider().frame(height: Self.dividerHeight)
            detail(title: "Duration", value: duration)
            Divider().frame(height: Self.dividerHeight)
            detail(title: "Style", value: style)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    /// Each column takes an equal share. Without this the four columns bunch
    /// together in the middle of a card that is now wider than they are.
    private func detail(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}
