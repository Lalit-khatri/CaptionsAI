@testable import CaptionsAI
import AVFoundation
import SwiftData
import XCTest

/// Tests for the fixtures themselves.
///
/// A broken fixture produces false greens everywhere downstream, so the seam
/// gets the same scrutiny as the code under test.
final class TestSupportTests: XCTestCase {
    @MainActor
    func testInMemoryContainerRoundTripsAProject() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = container.mainContext

        let project = Project(name: "Round trip", videoURL: URL(fileURLWithPath: "/tmp/x.mp4"))
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Round trip")
    }

    @MainActor
    func testInMemoryContainersAreIsolated() throws {
        let first = try TestSupport.makeInMemoryContainer()
        first.mainContext.insert(Project(videoURL: URL(fileURLWithPath: "/tmp/x.mp4")))
        try first.mainContext.save()

        // A leak between containers would let one test's data change another's
        // result, which is the hardest kind of false green to track down.
        let second = try TestSupport.makeInMemoryContainer()
        let fetched = try second.mainContext.fetch(FetchDescriptor<Project>())
        XCTAssertTrue(fetched.isEmpty, "in-memory stores must not share state")
    }

    func testFixtureVideoIsDecodableWithTheRequestedShape() async throws {
        let url = try await TestSupport.makeTestVideo(
            seconds: 1.0,
            size: CGSize(width: 320, height: 180),
            fps: 30
        )
        addTeardownBlock { TestSupport.remove(url) }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.1)

        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "fixture has no video track")

        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))

        let rate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(rate, 30, accuracy: 1.0)
    }

    func testFixtureFrameRateIsHonoured() async throws {
        // B19 asserts the exporter must follow the source frame rate, so the
        // fixture generator has to be able to produce something other than 30.
        let url = try await TestSupport.makeTestVideo(seconds: 1.0, fps: 60)
        addTeardownBlock { TestSupport.remove(url) }

        let asset = AVURLAsset(url: url)
        // The await has to be hoisted: XCTUnwrap takes a non-async autoclosure,
        // so an `await` inside its argument does not compile.
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "fixture has no video track")
        let rate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(rate, 60, accuracy: 1.0)
    }
}
