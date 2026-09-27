@testable import CaptionsAI
import SwiftData
import XCTest

/// The launch arguments the UI tests use, and the libraries they get.
///
/// The point of the seam is that a UI test never reads or writes the real
/// library, and that an ordinary launch is unaffected. Both are pinned here.
final class UITestLaunchTests: XCTestCase {
    // MARK: - Parsing

    func testAnOrdinaryLaunchAsksForNothing() {
        XCTAssertEqual(UITestLaunch(arguments: ["/path/to/CaptionsAI"]), .none)
    }

    func testTheSystemsOwnArgumentsAskForNothing() {
        let launch = UITestLaunch(arguments: ["CaptionsAI", "-NSDoubleLocalizedStrings", "YES", "-hasCompletedOnboarding", "YES"])

        XCTAssertEqual(launch, .none)
    }

    func testTheInMemoryFlagAsksForAnEmptyInMemoryStore() {
        XCTAssertEqual(
            UITestLaunch(arguments: ["CaptionsAI", "-uiTestInMemoryStore"]),
            UITestLaunch(usesInMemoryStore: true, seed: nil)
        )
    }

    func testEachSeedIsReadByName() {
        XCTAssertEqual(
            UITestLaunch(arguments: ["CaptionsAI", "-uiTestSeed", "projectWithCaptions"]).seed,
            .projectWithCaptions
        )
        XCTAssertEqual(
            UITestLaunch(arguments: ["CaptionsAI", "-uiTestSeed", "emptyProject"]).seed,
            .emptyProject
        )
    }

    /// A test that meant to seed must still never touch the real library.
    func testASeedImpliesAnInMemoryStore() {
        XCTAssertTrue(UITestLaunch(arguments: ["CaptionsAI", "-uiTestSeed", "emptyProject"]).usesInMemoryStore)
    }

    func testAnUnknownSeedIsIgnoredButStaysInMemory() {
        XCTAssertEqual(
            UITestLaunch(arguments: ["CaptionsAI", "-uiTestSeed", "nonsense"]),
            UITestLaunch(usesInMemoryStore: true, seed: nil)
        )
    }

    func testASeedFlagWithNoValueStaysInMemoryWithNoSeed() {
        XCTAssertEqual(
            UITestLaunch(arguments: ["CaptionsAI", "-uiTestSeed"]),
            UITestLaunch(usesInMemoryStore: true, seed: nil)
        )
    }

    /// The UI tests pass these strings; renaming a case would break them
    /// silently, since an unknown seed is ignored.
    func testSeedNamesAreTheOnesTheUITestsPass() {
        XCTAssertEqual(UITestLaunch.Seed.allCases.map(\.rawValue), ["projectWithCaptions", "emptyProject"])
    }

    // MARK: - The store

    func testAnOrdinaryLaunchGetsNoTestContainer() throws {
        XCTAssertNil(try UITestLaunch.none.makeTestContainer())
    }

    @MainActor
    func testAnEmptyInMemoryStoreHasNoProjects() throws {
        let container = try XCTUnwrap(UITestLaunch(usesInMemoryStore: true).makeTestContainer())

        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Project>()), 0)
    }

    @MainActor
    func testTheCaptionedSeedIsOneProjectWithItsTwoCaptionsInOrder() throws {
        let container = try XCTUnwrap(UITestLaunch(seed: .projectWithCaptions).makeTestContainerForSeed())

        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.map(\.name), ["UI Test Project"])
        XCTAssertEqual(projects.first?.sortedSegments.map(\.text), ["Hello from the UI tests", "A second caption"])
        XCTAssertEqual(projects.first?.sortedSegments.map(\.startTime), [0, 2])
    }

    @MainActor
    func testTheEmptySeedIsOneProjectWithNoCaptions() throws {
        let container = try XCTUnwrap(UITestLaunch(seed: .emptyProject).makeTestContainerForSeed())

        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.map(\.name), ["UI Test Project"])
        XCTAssertEqual(projects.first?.segments.count, 0)
    }

    /// The editor must open without transcribing and show the missing-video
    /// screen, so the seeded video must not resolve.
    @MainActor
    func testTheSeededProjectsVideoIsMissing() throws {
        let container = try XCTUnwrap(UITestLaunch(seed: .emptyProject).makeTestContainerForSeed())

        let project = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Project>()).first)
        XCTAssertNil(project.videoURL)
    }
}

private extension UITestLaunch {
    /// `init(usesInMemoryStore:seed:)` leaves the flag to the caller; the
    /// parser is what sets it for a seed. Mirror that here.
    func makeTestContainerForSeed() throws -> ModelContainer? {
        var launch = self
        launch.usesInMemoryStore = true
        return try launch.makeTestContainer()
    }
}
