@testable import CaptionsAI
import SwiftData
import XCTest

/// Whether deleting a caption deletes it.
///
/// The defect: removal only took the segment out of `project.segments`. The
/// `@Relationship(deleteRule: .cascade)` fires when the *project* is deleted,
/// not when a child is detached, so the row stayed in the store with
/// `project == nil`. Invisible to every screen, and permanent.
///
/// Two paths reach it. Swipe-delete in the transcript sheet orphans one row;
/// re-running transcription orphaned the entire previous transcript, once per
/// run.
///
/// These assert against a fetch of the store rather than the project's array,
/// because the array was never the thing that was wrong.
@MainActor
final class SegmentDeletionTests: XCTestCase {
    private func makeProject(in context: ModelContext, captions: [String]) throws -> Project {
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        for (index, text) in captions.enumerated() {
            project.addSegment(
                CaptionSegment(startTime: Double(index), endTime: Double(index) + 1, text: text)
            )
        }
        try context.save()
        return project
    }

    private func storedCaptions(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<CaptionSegment>()).map(\.text).sorted()
    }

    // MARK: - Swipe-delete

    func testDeletingACaptionRemovesItFromTheStore() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["first", "second"])
        let doomed = try XCTUnwrap(project.sortedSegments.first { $0.text == "first" })

        EditorViewModel(project: project).deleteSegment(doomed)
        try context.save()

        XCTAssertEqual(try storedCaptions(context), ["second"])
    }

    func testDeletingACaptionLeavesNoRowWithoutAProject() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["first", "second"])
        let doomed = try XCTUnwrap(project.sortedSegments.first)

        EditorViewModel(project: project).deleteSegment(doomed)
        try context.save()

        let orphans = try context.fetch(FetchDescriptor<CaptionSegment>())
            .filter { $0.project == nil }
        XCTAssertTrue(orphans.isEmpty, "orphaned rows: \(orphans.map(\.text))")
    }

    func testDeletingACaptionKeepsTheOthers() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["a", "b", "c"])
        let doomed = try XCTUnwrap(project.sortedSegments.first { $0.text == "b" })

        EditorViewModel(project: project).deleteSegment(doomed)
        try context.save()

        XCTAssertEqual(try storedCaptions(context), ["a", "c"])
        XCTAssertEqual(project.sortedSegments.map(\.text), ["a", "c"])
    }

    // MARK: - Re-running transcription

    func testReplacingTheTranscriptDoesNotLeaveThePreviousOneBehind() async throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["old one", "old two"])

        let fake = FakeTranscriber()
        fake.behaviour = .succeed([
            CaptionSegment(startTime: 0, endTime: 1, text: "new one"),
        ])

        await EditorViewModel(project: project, speechRecognizer: fake).generateCaptions()
        try context.save()

        XCTAssertEqual(try storedCaptions(context), ["new one"])
    }

    /// Every run used to leave a full transcript behind, so the store grew
    /// without bound while the app showed one transcript.
    func testRepeatedRunsDoNotAccumulateRows() async throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["original"])

        for run in 1 ... 3 {
            let fake = FakeTranscriber()
            fake.behaviour = .succeed([
                CaptionSegment(startTime: 0, endTime: 1, text: "run \(run)"),
            ])
            await EditorViewModel(project: project, speechRecognizer: fake).generateCaptions()
        }
        try context.save()

        XCTAssertEqual(try storedCaptions(context), ["run 3"])
    }

    // MARK: - Regression

    /// Deleting the project must still take its captions with it.
    func testDeletingAProjectStillCascades() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context, captions: ["a", "b"])

        context.delete(project)
        try context.save()

        XCTAssertEqual(try storedCaptions(context), [])
    }
}
