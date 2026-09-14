@testable import CaptionsAI
import Foundation
import SwiftData
import SwiftUI
import XCTest

/// What the editor does when the project's video is gone.
///
/// Videos can go: the user deletes them from Photos-adjacent storage, a
/// restore drops them, a beta build wrote a path that no longer resolves.
/// Today three failures stack silently. The view model skips making a player
/// and says nothing; the editor draws an unexplained grey rectangle with a
/// film glyph, which is indistinguishable from a video that has not loaded
/// yet; and Export runs `guard let videoURL = project.videoURL else { return }`
/// — a button that does nothing at all when pressed.
@MainActor
final class MissingVideoTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func projectWithRealVideo() throws -> (Project, URL) {
        let reference = try VideoLibrary.store(data: Data("video".utf8))
        let url = try XCTUnwrap(VideoLibrary.resolve(reference))
        written.append(url)
        return (Project(name: "Here", videoURL: url), url)
    }

    private func projectWithNoVideo() -> Project {
        Project(
            name: "Gone",
            videoURL: URL(fileURLWithPath: "/tmp/captionsai-absent-\(UUID().uuidString).mov")
        )
    }

    // MARK: - Noticing

    func testAProjectWhoseVideoIsPresentIsNotReportedMissing() throws {
        let (project, _) = try projectWithRealVideo()

        XCTAssertFalse(EditorViewModel(project: project).videoIsMissing)
    }

    func testAProjectWhoseVideoIsGoneIsReportedMissing() {
        XCTAssertTrue(EditorViewModel(project: projectWithNoVideo()).videoIsMissing)
    }

    /// Answered once, at construction, and remembered.
    ///
    /// `project.videoURL` is not a stored property — it calls through to
    /// `VideoLibrary.resolve`, which hits the filesystem. Reading it from a
    /// `body` means a `stat` per frame, on the screen that is also decoding
    /// video. Deleting the file behind a live view model and seeing the answer
    /// *not* change is how you tell a cached value from a recomputed one.
    func testTheAnswerIsCachedRatherThanRecheckedOnEveryRead() throws {
        let (project, url) = try projectWithRealVideo()
        let viewModel = EditorViewModel(project: project)
        XCTAssertFalse(viewModel.videoIsMissing, "precondition")

        try FileManager.default.removeItem(at: url)

        XCTAssertFalse(
            viewModel.videoIsMissing,
            "the editor re-stats the video file on every read of this property"
        )
    }

    // MARK: - Saying so

    func testTheMissingVideoCopyExplainsWhatIsWrongAndWhatToDo() {
        let copy = (MissingVideoView.title + " " + MissingVideoView.message).lowercased()

        XCTAssertTrue(copy.contains("video"), copy)
        XCTAssertTrue(
            copy.contains("moved") || copy.contains("deleted") || copy.contains("no longer"),
            "the copy does not say what happened: \(copy)"
        )
        XCTAssertTrue(
            copy.contains("import"),
            "the copy does not say what to do about it: \(copy)"
        )
    }

    func testTheMissingVideoNoticeRenders() throws {
        let renderer = ImageRenderer(content: MissingVideoView().frame(width: 393, height: 400))
        renderer.scale = 1

        XCTAssertNotNil(renderer.uiImage)
    }

    // MARK: - Not offering what cannot work

    /// Export currently guards on the URL and silently returns. A button that
    /// does nothing when pressed is worse than a disabled one: the user
    /// presses it again.
    func testExportIsNotOfferedWhenThereIsNoVideoToExport() {
        XCTAssertFalse(EditorView.exportIsAvailable(videoIsMissing: true))
        XCTAssertTrue(EditorView.exportIsAvailable(videoIsMissing: false))
    }

    /// And transcription already had the right answer — it sets an error
    /// rather than failing silently. Pinned here because the whole point of
    /// this change is that the three paths agree.
    func testTranscribingAMissingVideoStillReportsAnError() async {
        let viewModel = EditorViewModel(project: projectWithNoVideo())

        await viewModel.generateCaptions()

        XCTAssertEqual(viewModel.error, "Video file not found")
    }
}
