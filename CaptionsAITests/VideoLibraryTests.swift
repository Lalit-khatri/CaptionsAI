@testable import CaptionsAI
import Foundation
import SwiftData
import XCTest

/// Where a project's video lives, and whether it can still be found later.
///
/// The defect: imports were written to `tmp/`, which iOS reclaims without
/// warning, and the resulting **absolute** path was persisted. A container
/// UUID changes on reinstall, so the path is wrong even when the file was
/// never touched. Both failures are silent — `thumbnailData` is in the
/// database and keeps rendering, so the project list looks healthy over a
/// video that will never load.
final class VideoLibraryTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func storeFixture(_ bytes: Data = Data("video".utf8)) throws -> String {
        let name = try VideoLibrary.store(data: bytes)
        if let url = VideoLibrary.resolve(name) { written.append(url) }
        return name
    }

    // MARK: - Where the file goes

    func testAnImportedVideoIsNotLeftInTheTemporaryDirectory() throws {
        let name = try storeFixture()
        let url = try XCTUnwrap(VideoLibrary.resolve(name))

        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertFalse(
            url.standardizedFileURL.path.hasPrefix(temp),
            "the video is in a directory iOS reclaims: \(url.path)"
        )
        XCTAssertTrue(url.path.contains("Application Support"), url.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testStoringTwiceDoesNotCollide() throws {
        let first = try storeFixture(Data("one".utf8))
        let second = try storeFixture(Data("two".utf8))
        XCTAssertNotEqual(first, second)

        let firstURL = try XCTUnwrap(VideoLibrary.resolve(first))
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("one".utf8))
    }

    // MARK: - What gets persisted

    func testAProjectRecordsAFileNameRatherThanAPath() throws {
        let name = try storeFixture()
        let url = try XCTUnwrap(VideoLibrary.resolve(name))

        let project = Project(name: "P", videoURL: url)

        XCTAssertFalse(
            project.videoURLString.contains("/"),
            "a path was persisted, and paths do not survive reinstall: \(project.videoURLString)"
        )
        XCTAssertEqual(project.videoURLString, name)
        XCTAssertEqual(project.videoURL, url)
    }

    /// The reinstall case, which is the one that actually loses projects.
    ///
    /// The file never moves; the *container* does. A project written by the
    /// previous build holds a path under the old container UUID, and must
    /// still find its video.
    func testAProjectSurvivesTheContainerDirectoryChanging() throws {
        let name = try storeFixture()
        let url = try XCTUnwrap(VideoLibrary.resolve(name))

        let project = Project(name: "P", videoURL: url)
        project.videoURLString = "file:///var/mobile/Containers/Data/Application/"
            + "00000000-DEAD-BEEF-0000-000000000000/Library/Application%20Support/Videos/"
            + name

        XCTAssertEqual(
            project.videoURL, url,
            "a stale container path should still resolve by file name"
        )
    }

    func testAnAbsolutePathOutsideTheLibraryIsHonouredWhileItExists() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).mp4")
        try Data("x".utf8).write(to: outside)
        written.append(outside)

        let project = Project(name: "P", videoURL: outside)
        XCTAssertEqual(project.videoURL?.standardizedFileURL, outside.standardizedFileURL)
    }

    /// A reference to a file that is genuinely gone must read as gone. The old
    /// behaviour returned a well-formed URL pointing at nothing, so every
    /// caller's `guard let url` succeeded and the failure surfaced much later
    /// as a black frame.
    func testAMissingVideoResolvesToNil() throws {
        let name = try storeFixture()
        let url = try XCTUnwrap(VideoLibrary.resolve(name))
        try FileManager.default.removeItem(at: url)

        XCTAssertNil(VideoLibrary.resolve(name))
        XCTAssertNil(Project(name: "P", videoURL: url).videoURL)
    }

    // MARK: - Reclaiming space

    func testDeletingAProjectRemovesItsVideo() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)

        let name = try storeFixture()
        let url = try XCTUnwrap(VideoLibrary.resolve(name))
        let project = Project(name: "P", videoURL: url)
        context.insert(project)
        try context.save()

        ImportViewModel().deleteProject(project, context: context)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "the video outlived its project, and nothing else will ever delete it"
        )
    }

    func testRemoveWillNotDeleteAFileOutsideTheLibrary() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-\(UUID().uuidString).mp4")
        try Data("x".utf8).write(to: outside)
        written.append(outside)

        VideoLibrary.remove(outside.absoluteString)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outside.path),
            "the library deleted a file it does not own"
        )
    }
}
