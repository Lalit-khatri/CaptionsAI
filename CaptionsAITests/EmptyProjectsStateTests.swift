@testable import CaptionsAI
import SwiftUI
import UIKit
import XCTest

/// What the home screen shows when the library is empty.
///
/// Until now it showed nothing: the "Recent Projects" heading and its strip
/// were wrapped in `if !recentProjects.isEmpty`, so a first-run user saw the
/// import box and then blank space, with no confirmation that the app had
/// looked and found nothing rather than failed to look.
@MainActor
final class EmptyProjectsStateTests: XCTestCase {
    private func render(_ view: some View, width: CGFloat = 393) throws -> CGSize {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "the view did not render").size
    }

    // MARK: - When it appears

    func testTheEmptyStateAppearsWhenThereAreNoProjects() {
        XCTAssertTrue(ImportView.showsEmptyState(projectCount: 0))
    }

    func testTheEmptyStateIsGoneAsSoonAsThereIsOneProject() {
        XCTAssertFalse(ImportView.showsEmptyState(projectCount: 1))
    }

    /// The strip is capped at ten, but the cap is not what decides this — a
    /// library of five hundred still has projects to show.
    func testAFullStripStillShowsProjectsRatherThanTheEmptyState() {
        XCTAssertFalse(ImportView.showsEmptyState(projectCount: ImportViewModel.recentProjectsLimit))
        XCTAssertFalse(ImportView.showsEmptyState(projectCount: 500))
    }

    // MARK: - What it says

    func testTheCopyIsPresentAndShort() {
        XCTAssertFalse(EmptyProjectsView.title.isEmpty)
        XCTAssertFalse(EmptyProjectsView.message.isEmpty)
        XCTAssertLessThanOrEqual(EmptyProjectsView.title.count, 24, "a title, not a sentence")
        XCTAssertLessThanOrEqual(EmptyProjectsView.message.count, 80)
    }

    /// The copy must not promise anything the screen cannot do yet. There is
    /// currently no way to browse past the tenth project, so the empty state
    /// must not say "your ten most recent" or name a number at all.
    func testTheCopyDoesNotNameANumber() {
        let copy = EmptyProjectsView.title + " " + EmptyProjectsView.message

        XCTAssertNil(
            copy.rangeOfCharacter(from: CharacterSet.decimalDigits),
            "the empty state names a count the screen cannot yet honour"
        )
    }

    /// It is an absence, not an error. "No projects" is a statement of fact;
    /// "failed", "error" and "unable" would be a lie.
    func testTheCopyDoesNotReadAsAFailure() {
        let copy = (EmptyProjectsView.title + " " + EmptyProjectsView.message).lowercased()

        for alarming in ["error", "fail", "unable", "problem", "sorry"] {
            XCTAssertFalse(copy.contains(alarming), "empty state reads as a failure: \(alarming)")
        }
    }

    // MARK: - How big it is

    func testTheEmptyStateRenders() throws {
        XCTAssertGreaterThan(try render(EmptyProjectsView()).height, 0)
    }

    /// It sits *below* the import call to action, which is the thing a
    /// first-run user is meant to press. On an iPhone SE the content area is
    /// 603pt and the import box plus its button already take the bulk of it, so
    /// an empty state that renders as a second hero block pushes the real
    /// action off screen. `ContentUnavailableView` is used without a symbol for
    /// exactly this reason — the screen already has a `film.stack` glyph in the import box,
    /// and a second one below it would be the tallest thing on the page.
    func testTheEmptyStateIsAFootnoteRatherThanASecondHero() throws {
        let height = try render(EmptyProjectsView()).height

        XCTAssertLessThanOrEqual(height, 220, "the empty state has grown into a hero block")
    }

    /// Narrow phones are where a fixed-width empty state breaks. The copy has
    /// to reflow rather than truncate or clip.
    func testTheEmptyStateSurvivesASmallPhoneWidth() throws {
        let narrow = try render(EmptyProjectsView(), width: 320)
        let wide = try render(EmptyProjectsView(), width: 393)

        XCTAssertEqual(narrow.width, 320, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(narrow.height, wide.height, "the copy did not reflow")
    }
}
