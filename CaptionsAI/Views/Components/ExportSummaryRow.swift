import SwiftUI

/// The "Format / Duration / Style" card under the success thumbnail
/// on the export-completion screen.
///
/// Lifted out of `ExportView.completedView` unchanged. It takes plain
/// strings rather than reading a view model, so a test can render it: the
/// columns are the part of that screen whose width behaviour is in question,
/// and there is no way to put the screen itself in front of `ImageRenderer`.
struct ExportSummaryRow: View {
    let format: String
    let duration: String
    let style: String

    static let cornerRadius: CGFloat = 12
    static let columnSpacing: CGFloat = 16
    static let dividerHeight: CGFloat = 28

    struct Column: Equatable {
        let title: String
        let value: String
    }

    /// The columns, left to right, as data so a test can state what the card
    /// says without drawing it. Titles are unique, which makes them the
    /// `ForEach` identity.
    var columns: [Column] {
        [
            Column(title: "Format", value: format),
            Column(title: "Duration", value: duration),
            Column(title: "Style", value: style),
        ]
    }

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns, id: \.title) { column in
                if column.title != columns.first?.title {
                    Divider().frame(height: Self.dividerHeight)
                }
                detail(title: column.title, value: column.value)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    /// Each column takes an equal share. Without this the columns bunch
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
