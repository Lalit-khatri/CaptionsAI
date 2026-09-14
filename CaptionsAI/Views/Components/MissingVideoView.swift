import SwiftUI

// MARK: - MissingVideoView

/// Shown in the editor's video area when the project's video file is gone.
///
/// It replaces a grey rectangle with a film glyph, which said nothing: that is
/// exactly what a video looks like before it loads, so a permanent failure and
/// a momentary one were drawn identically and the user had no reason to stop
/// waiting.
///
/// Sized by its parent's `GeometryReader` rather than by itself. It sits where
/// the video would be, which on a tall clip is most of the screen and on a
/// short one is not much, so anything with its own fixed height would be wrong
/// in one of those cases.
struct MissingVideoView: View {
    static let title = "Video unavailable"
    static let message = "This project's video has been moved or deleted. Import it again to keep working."

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))

            ContentUnavailableView {
                Label(Self.title, systemImage: "film.slash")
            } description: {
                Text(Self.message)
            }
        }
    }
}
