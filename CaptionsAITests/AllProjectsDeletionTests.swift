@testable import CaptionsAI
import Foundation
import SwiftData
import XCTest

/// Deleting a project from the full list.
///
/// The home strip's context menu was the only delete path in the app, and it
/// removes the video file as well as the row — nothing else ever will, so a
/// second delete path that forgets to is a permanent leak of whole videos.
/// This suite exists to make sure the two paths are one path.
@MainActor
final class AllProjectsDeletionTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    /// A project whose video is genuinely on disk, so that "the file is gone"
    /// is a real observation rather than a vacuous one.
    private func makeProjectWithVideo(
        named name: String,
        in context: ModelContext
    ) throws -> (project: Project, video: URL) {
        let reference = try VideoLibrary.store(data: Data("video-\(name)".utf8))
        let url = try XCTUnwrap(VideoLibrary.resolve(reference))
        written.append(url)

        let project = Project(name: name, videoURL: url)
        context.insert(project)
        try context.save()
        return (project, url)
    }

    // MARK: - The delete itself

    func testDeletingFromTheFullListRemovesTheProject() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let (project, _) = try makeProjectWithVideo(named: "gone", in: context)

        AllProjectsView.delete(project, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
    }

    /// The point of the whole suite.
    func testDeletingFromTheFullListAlsoRemovesTheVideoFile() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let (project, video) = try makeProjectWithVideo(named: "gone", in: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path), "precondition")

        AllProjectsView.delete(project, context: context)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: video.path),
            "the video outlived its project, and nothing else will ever delete it"
        )
    }

    func testDeletingOneProjectLeavesTheOthersAndTheirVideosAlone() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let (doomed, doomedVideo) = try makeProjectWithVideo(named: "doomed", in: context)
        let (_, keptVideo) = try makeProjectWithVideo(named: "kept", in: context)

        AllProjectsView.delete(doomed, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: doomedVideo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptVideo.path))
    }

    /// Two lists, one deleter. If these ever diverge, one of them is leaking
    /// video files and nobody will notice until the device fills up.
    func testBothDeletePathsBehaveIdentically() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let (viaStrip, stripVideo) = try makeProjectWithVideo(named: "strip", in: context)
        let (viaList, listVideo) = try makeProjectWithVideo(named: "list", in: context)

        ImportViewModel().deleteProject(viaStrip, context: context)
        AllProjectsView.delete(viaList, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stripVideo.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: listVideo.path))
    }

    // MARK: - Making it hard to do by accident

    /// `.swipeActions` defaults to `allowsFullSwipe: true`, which fires the
    /// first destructive button on a long swipe with no tap on it at all. For
    /// a row whose delete is unrecoverable and takes a video file with it,
    /// that is a gesture away from losing work.
    func testAFullSwipeCannotDelete() {
        XCTAssertFalse(AllProjectsView.allowsFullSwipeDelete)
    }

    func testTheConfirmationNamesTheProject() {
        XCTAssertTrue(AllProjectsView.deletePrompt(for: "Beach clip").contains("Beach clip"))
    }

    /// It must say what is actually lost. The row is the visible thing, but
    /// the video file goes too and there is no undo.
    func testTheConfirmationSaysTheVideoGoesAndThatItIsFinal() {
        let prompt = AllProjectsView.deletePrompt(for: "Beach clip").lowercased()

        XCTAssertTrue(prompt.contains("video"), prompt)
        XCTAssertTrue(
            prompt.contains("can't be undone") || prompt.contains("cannot be undone"),
            prompt
        )
    }
}
