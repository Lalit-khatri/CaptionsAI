@testable import CaptionsAI
import SwiftData
import SwiftUI
import XCTest

/// Reaching the projects the home strip does not show.
///
/// The strip is capped at ten. Without a way past it the cap is not a window,
/// it is a wall: the eleventh project still exists, still occupies disk, and
/// has become unreachable. These tests cover the affordance that opens it and
/// the route it opens.
@MainActor
final class AllProjectsRouteTests: XCTestCase {
    @discardableResult
    private func insertProjects(_ count: Int, into container: ModelContainer) throws -> [String] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var names: [String] = []
        for index in 0 ..< count {
            let name = String(format: "P%02d", index)
            names.append(name)
            container.mainContext.insert(
                Project(
                    name: name,
                    videoURL: TestSupport.placeholderVideoURL,
                    createdAt: base,
                    modifiedAt: base.addingTimeInterval(Double(index) * 60)
                )
            )
        }
        try container.mainContext.save()
        return names
    }

    // MARK: - Knowing there is more

    /// The strip cannot answer this question about itself: capped at ten, a
    /// library of ten and a library of five hundred both load ten rows.
    func testTheViewModelKnowsHowManyProjectsExistBeyondTheStrip() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.recentProjects.count, 10)
        XCTAssertEqual(viewModel.totalProjectCount, 12)
    }

    func testTheTotalIsExactBelowTheCapToo() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(3, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.totalProjectCount, 3)
    }

    func testAnEmptyLibraryCountsZero() throws {
        let container = try TestSupport.makeInMemoryContainer()

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.totalProjectCount, 0)
    }

    // MARK: - Offering the way through

    /// Offered only when it leads somewhere new. At exactly ten the strip is
    /// already the whole library and "See All" would open a screen showing the
    /// same ten rows.
    func testSeeAllIsOfferedOnlyWhenSomethingIsHidden() {
        XCTAssertFalse(ImportView.showsSeeAll(totalProjectCount: 0))
        XCTAssertFalse(ImportView.showsSeeAll(totalProjectCount: 1))
        XCTAssertFalse(ImportView.showsSeeAll(totalProjectCount: 10))
        XCTAssertTrue(ImportView.showsSeeAll(totalProjectCount: 11))
        XCTAssertTrue(ImportView.showsSeeAll(totalProjectCount: 500))
    }

    /// Stated against the constant rather than the literal, so that changing
    /// the cap cannot leave the affordance behind.
    func testTheThresholdIsTheCapItself() {
        let cap = ImportViewModel.recentProjectsLimit

        XCTAssertFalse(ImportView.showsSeeAll(totalProjectCount: cap))
        XCTAssertTrue(ImportView.showsSeeAll(totalProjectCount: cap + 1))
    }

    // MARK: - The route

    func testTheAllProjectsScreenIsItsOwnDestination() {
        XCTAssertEqual(AppScreen.allProjects, AppScreen.allProjects)
        XCTAssertNotEqual(AppScreen.allProjects, AppScreen.paywall)
        XCTAssertNotEqual(AppScreen.allProjects, AppScreen.importVideo)
    }

    /// `AppScreen` hand-writes `hash(into:)`, so a new case whose hash was not
    /// added collides with whatever the switch happened to fall through to.
    func testTheAllProjectsScreenHashesToItself() {
        XCTAssertEqual(AppScreen.allProjects.hashValue, AppScreen.allProjects.hashValue)
        XCTAssertNotEqual(AppScreen.allProjects.hashValue, AppScreen.paywall.hashValue)
        XCTAssertNotEqual(AppScreen.allProjects.hashValue, AppScreen.importVideo.hashValue)
    }

    // MARK: - The screen

    func testTheAllProjectsScreenBuildsAgainstARealStore() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let renderer = ImageRenderer(
            content: NavigationStack { AllProjectsView() }
                .frame(width: 393, height: 700)
                .modelContainer(container)
        )
        renderer.scale = 1

        XCTAssertNotNil(renderer.uiImage, "the all-projects screen did not render")
    }

    func testTheScreenTitleDoesNotClaimACount() {
        XCTAssertFalse(AllProjectsView.title.isEmpty)
        XCTAssertNil(
            AllProjectsView.title.rangeOfCharacter(from: CharacterSet.decimalDigits),
            "the title names a number that will be wrong the moment a project is added"
        )
    }
}
