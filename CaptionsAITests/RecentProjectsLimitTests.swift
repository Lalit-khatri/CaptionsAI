@testable import CaptionsAI
import SwiftData
import XCTest

/// How many projects the home screen loads.
///
/// The fetch had no limit, so the "Recent" strip was the whole library: every
/// project ever made, every row holding a decoded thumbnail, re-read on every
/// appearance. The cap is a *window*, not a cull — the eleventh project is
/// still there, still openable, and must never be deleted to make the list
/// short. These tests assert both halves of that.
@MainActor
final class RecentProjectsLimitTests: XCTestCase {
    /// `count` projects named P00, P01, ... with strictly increasing
    /// `modifiedAt`, so the newest is the highest-numbered.
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

    private func everyStoredProject(in container: ModelContainer) throws -> [Project] {
        try container.mainContext.fetch(FetchDescriptor<Project>())
    }

    // MARK: - The cap

    func testTheLimitIsTen() {
        XCTAssertEqual(ImportViewModel.recentProjectsLimit, 10)
    }

    func testOnlyTenAreLoadedWhenTwelveExist() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.recentProjects.count, 10)
    }

    func testFewerThanTenAreAllLoaded() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(3, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.recentProjects.count, 3)
    }

    func testAnEmptyStoreLoadsNothingRatherThanFailing() throws {
        let container = try TestSupport.makeInMemoryContainer()

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.recentProjects, [])
    }

    // MARK: - Which ten

    /// A limit applied to the wrong end of the sort is worse than no limit: it
    /// hides the work you just did and shows the work you abandoned.
    func testTheTenLoadedAreTheMostRecentlyModified() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(
            viewModel.recentProjects.map(\.name),
            ["P11", "P10", "P09", "P08", "P07", "P06", "P05", "P04", "P03", "P02"]
        )
    }

    // MARK: - A window, not a cull

    /// The whole risk of this change is that "show ten" quietly becomes "keep
    /// ten". Loading the strip must leave every project on disk.
    func testLoadingTheStripDeletesNothing() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(try everyStoredProject(in: container).count, 12)
    }

    /// And because it is a window, removing one of the visible ten slides the
    /// eleventh up into view rather than leaving a gap.
    func testRemovingAVisibleProjectPromotesTheNextOneDown() throws {
        let container = try TestSupport.makeInMemoryContainer()
        try insertProjects(12, into: container)

        let viewModel = ImportViewModel()
        viewModel.loadRecentProjects(context: container.mainContext)
        XCTAssertFalse(viewModel.recentProjects.contains { $0.name == "P01" }, "precondition")

        let newest = try XCTUnwrap(viewModel.recentProjects.first)
        container.mainContext.delete(newest)
        try container.mainContext.save()
        viewModel.loadRecentProjects(context: container.mainContext)

        XCTAssertEqual(viewModel.recentProjects.count, 10)
        XCTAssertTrue(viewModel.recentProjects.contains { $0.name == "P01" })
    }
}
