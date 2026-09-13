@testable import CaptionsAI
import AVFoundation
import XCTest

/// Whether the app clears up after an export.
///
/// The defect: every export wrote `CaptionsAI_<uuid>.mp4` into the temporary
/// directory and nothing ever deleted it. The file leaves the user's reach the
/// moment the next export starts, but it stays on disk — so a few dozen
/// renders of a long video quietly held on to gigabytes. iOS purges `tmp`
/// under storage pressure, but not on behalf of the app that is still holding
/// the space.
@MainActor
final class ExportScratchTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scratch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func write(_ name: String) -> URL {
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    private var remaining: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: - Clearing up

    func testEarlierExportsAreDeleted() {
        write("\(ExportEngine.scratchPrefix)one.mp4")
        write("\(ExportEngine.scratchPrefix)two.mov")

        let removed = ExportEngine.removeStaleExports(in: directory)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(remaining, [])
    }

    func testTheExportBeingOfferedIsKept() {
        write("\(ExportEngine.scratchPrefix)old.mp4")
        let current = write("\(ExportEngine.scratchPrefix)current.mp4")

        ExportEngine.removeStaleExports(in: directory, keeping: current)

        XCTAssertEqual(remaining, ["\(ExportEngine.scratchPrefix)current.mp4"])
    }

    // MARK: - Nothing else is touched

    func testFilesTheAppDidNotWriteAreLeftAlone() {
        write("\(ExportEngine.scratchPrefix)mine.mp4")
        write("holiday.mp4")
        write("notes.txt")

        ExportEngine.removeStaleExports(in: directory)

        XCTAssertEqual(remaining, ["holiday.mp4", "notes.txt"])
    }

    func testAnEmptyDirectoryIsFine() {
        XCTAssertEqual(ExportEngine.removeStaleExports(in: directory), 0)
    }

    func testAMissingDirectoryIsFine() {
        let gone = directory.appendingPathComponent("not-there")

        XCTAssertEqual(ExportEngine.removeStaleExports(in: gone), 0)
    }

    // MARK: - The engine actually does it

    /// Cleanup the engine never calls is worth nothing, so this runs two real
    /// exports and checks the first file is gone once the second starts.
    func testASecondExportClearsAwayTheFirst() async throws {
        let source = try await TestSupport.makeTestVideo(
            seconds: 0.5, size: CGSize(width: 320, height: 240), fps: 4
        )
        defer { TestSupport.remove(source) }

        let engine = ExportEngine()
        engine.photoLibrarySaver = { _ in }

        let first = try await engine.export(
            videoURL: source, settings: ExportSettings(), preset: .original,
            segments: [], style: .hormozi, captionYPosition: 0.8, addWatermark: false
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "the first export did not land")

        let second = try await engine.export(
            videoURL: source, settings: ExportSettings(), preset: .original,
            segments: [], style: .hormozi, captionYPosition: 0.8, addWatermark: false
        )
        defer { TestSupport.remove(second) }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: first.path),
            "\(first.lastPathComponent) is still in tmp after another export"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}
