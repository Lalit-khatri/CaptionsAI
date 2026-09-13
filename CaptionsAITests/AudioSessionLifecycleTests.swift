@testable import CaptionsAI
import AVFoundation
import SwiftData
import XCTest

/// Whether the editor gives the audio route back when the user leaves.
///
/// The defect: opening the editor claimed a `.playback` session, which
/// interrupts whatever else the phone is playing, and nothing ever released
/// it. Podcast or music stayed stopped after the user left the editor — and
/// after they left the app, until it was killed.
@MainActor
final class AudioSessionLifecycleTests: XCTestCase {
    private func makeViewModel(_ session: FakeAudioSession) throws -> EditorViewModel {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        try context.save()
        return EditorViewModel(project: project, audioSession: session)
    }

    // MARK: - Opening the editor

    func testOpeningTheEditorClaimsTheAudioRoute() throws {
        let session = FakeAudioSession()

        _ = try makeViewModel(session)

        XCTAssertTrue(session.isActive)
    }

    func testTheSessionIsConfiguredForWatchingAVideo() throws {
        let session = FakeAudioSession()

        _ = try makeViewModel(session)

        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .moviePlayback)
    }

    // MARK: - Leaving the editor

    func testLeavingTheEditorHandsTheAudioRouteBack() throws {
        let session = FakeAudioSession()
        let viewModel = try makeViewModel(session)

        viewModel.endPlaybackSession()

        XCTAssertFalse(
            session.isActive,
            "the editor is gone but the app still holds the audio session"
        )
    }

    func testLeavingTheEditorTellsTheInterruptedAppItCanResume() throws {
        let session = FakeAudioSession()
        let viewModel = try makeViewModel(session)

        viewModel.endPlaybackSession()

        let release = try XCTUnwrap(session.activations.last)
        XCTAssertTrue(
            release.options.contains(.notifyOthersOnDeactivation),
            "the session was released without notifying others, so the user's music stays paused"
        )
    }

    // MARK: - It holds the route for as long as it needs it

    func testTheEditorKeepsTheRouteWhileItIsStillOpen() throws {
        let session = FakeAudioSession()
        let viewModel = try makeViewModel(session)

        viewModel.setupTimeObserver()
        viewModel.selectStyle(try XCTUnwrap(CaptionStyle.presets.first))

        XCTAssertFalse(
            session.wasEverReleased,
            "the editor released the audio route while it was still on screen"
        )
        XCTAssertTrue(session.isActive)
    }

    func testLeavingTwiceIsHarmless() throws {
        let session = FakeAudioSession()
        let viewModel = try makeViewModel(session)

        viewModel.endPlaybackSession()
        viewModel.endPlaybackSession()

        XCTAssertFalse(session.isActive)
    }

    func testASecondEditorTakesTheRouteBack() throws {
        let session = FakeAudioSession()
        try makeViewModel(session).endPlaybackSession()

        _ = try makeViewModel(session)

        XCTAssertTrue(
            session.isActive,
            "reopening an editor after leaving one left the app without an audio route"
        )
    }
}
