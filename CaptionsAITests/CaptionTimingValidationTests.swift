@testable import CaptionsAI
import SwiftData
import XCTest

@MainActor
final class CaptionTimingValidationTests: XCTestCase {

    private func makeEditor(videoDuration: Double = 0) throws -> (EditorViewModel, Project, CaptionSegment) {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL, videoDuration: videoDuration)
        context.insert(project)

        let segment = CaptionSegment(
            startTime: 0,
            endTime: 2,
            text: "first caption",
            sortOrder: 0
        )
        project.addSegment(segment)
        try context.save()

        return (EditorViewModel(project: project), project, segment)
    }

    func testNegativeTimingIsClampedToZero() throws {
        let (editor, _, segment) = try makeEditor()

        editor.updateSegmentTiming(segment, start: -5.0, end: 2.0)

        XCTAssertGreaterThanOrEqual(segment.startTime, 0.0, "Start time should not be negative")
    }

    func testInvertedTimingIsClampedSoEndNeverPrecedesStart() throws {
        let (editor, _, segment) = try makeEditor()

        editor.updateSegmentTiming(segment, start: 5.0, end: 2.0)

        XCTAssertGreaterThanOrEqual(segment.endTime, segment.startTime, "End time must not precede start time")
    }

    func testTimingBeyondVideoDurationIsClamped() throws {
        let (editor, _, segment) = try makeEditor(videoDuration: 10.0)

        editor.updateSegmentTiming(segment, start: 8.0, end: 25.0)

        XCTAssertLessThanOrEqual(segment.endTime, 10.0, "End time should not exceed video duration")
    }

    func testRetimingReordersSegmentsChronologically() throws {
        let (editor, project, segmentA) = try makeEditor()
        let segmentB = CaptionSegment(startTime: 4.0, endTime: 6.0, text: "second caption", sortOrder: 1)
        project.addSegment(segmentB)
        editor.segments = project.sortedSegments

        // Retime segmentA from 0..2s to 8..10s, past segmentB
        editor.updateSegmentTiming(segmentA, start: 8.0, end: 10.0)

        let currentOrder = project.sortedSegments
        XCTAssertEqual(currentOrder.first?.id, segmentB.id, "Segment B should now be first in sortedSegments")
        XCTAssertEqual(currentOrder.last?.id, segmentA.id, "Segment A should now be last in sortedSegments")
        XCTAssertEqual(segmentB.sortOrder, 0)
        XCTAssertEqual(segmentA.sortOrder, 1)
    }
}
