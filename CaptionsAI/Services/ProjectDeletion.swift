import Foundation
import SwiftData

// MARK: - ProjectDeletion

/// Removing a project, everywhere, the same way.
///
/// Deleting a project is two operations, not one: the row goes through
/// SwiftData and the video file goes through ``VideoLibrary``. Nothing else in
/// the app ever cleans up a video — they are kept deliberately, outside `tmp/`,
/// precisely so that iOS will not reclaim them — so a delete path that only
/// does the first half leaks an entire video, permanently and invisibly.
///
/// There are now two places a project can be deleted from. This is the one
/// implementation, so there is one place to get it right.
enum ProjectDeletion {
    static func delete(_ project: Project, context: ModelContext) {
        // Read the reference before the delete, while the object is still
        // valid. Touching a deleted `PersistentModel` is a crash, not a nil.
        let videoReference = project.videoURLString

        context.delete(project)
        try? context.save()
        VideoLibrary.remove(videoReference)
    }
}
