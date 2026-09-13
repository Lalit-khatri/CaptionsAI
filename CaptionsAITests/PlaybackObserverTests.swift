@testable import CaptionsAI
import AVFoundation
import SwiftData
import XCTest

/// Whether the editor cleans up its playback observer.
///
/// The defect: `setupTimeObserver()` assigned a fresh token over the old one
/// without removing the old registration. The view calls it from `.onAppear`,
/// which fires again every time the editor comes back — so each visit left
/// another periodic observer running at 20 Hz, and `deinit` could only remove
/// the last of them.
///
/// `AVPlayer` will not report how many observers it holds, so the registration
/// goes through `PeriodicTimeObserving` and the test counts them there.
@MainActor
final class PlaybackObserverTests: XCTestCase {
    /// Stands in for the `AVPlayer`, and keeps count.
    private final class FakePlaybackClock: PeriodicTimeObserving {
        final class Token {}

        private var handlers: [ObjectIdentifier: (CMTime) -> Void] = [:]
        private var tokens: [Token] = []
        private(set) var registrations = 0

        var liveObserverCount: Int { handlers.count }

        func addPeriodicObserver(every _: CMTime, handler: @escaping (CMTime) -> Void) -> Any {
            registrations += 1
            let token = Token()
            tokens.append(token)
            handlers[ObjectIdentifier(token)] = handler
            return token
        }

        func removePeriodicObserver(_ token: Any) {
            guard let token = token as? Token else { return }
            handlers[ObjectIdentifier(token)] = nil
            tokens.removeAll { $0 === token }
        }

        /// Delivers a playback time to everything still registered.
        func tick(to seconds: Double) {
            for handler in handlers.values {
                handler(CMTime(seconds: seconds, preferredTimescale: 600))
            }
        }
    }

    private func makeEditor(clock: FakePlaybackClock) throws -> EditorViewModel {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        try context.save()
        return EditorViewModel(project: project, speechRecognizer: FakeTranscriber(), playbackClock: clock)
    }

    // MARK: - The leak

    func testComingBackToTheEditorDoesNotLeaveAnObserverBehind() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)

        editor.setupTimeObserver()
        editor.setupTimeObserver()
        editor.setupTimeObserver()

        XCTAssertEqual(clock.liveObserverCount, 1, "\(clock.registrations) registrations, \(clock.liveObserverCount) still live")
    }

    func testLeavingTheEditorStopsTheObserver() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)
        editor.setupTimeObserver()
        editor.setupTimeObserver()

        editor.teardownTimeObserver()

        XCTAssertEqual(clock.liveObserverCount, 0)
    }

    func testAStoppedObserverNoLongerReportsTime() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)
        editor.setupTimeObserver()
        clock.tick(to: 3)
        editor.teardownTimeObserver()

        clock.tick(to: 9)

        XCTAssertEqual(editor.currentPlaybackTime, 3)
    }

    // MARK: - Playback tracking still works

    func testTheObserverReportsPlaybackTime() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)
        editor.setupTimeObserver()

        clock.tick(to: 4.5)

        XCTAssertEqual(editor.currentPlaybackTime, 4.5, accuracy: 0.001)
    }

    func testTheEditorCanBeRestartedAfterBeingStopped() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)
        editor.setupTimeObserver()
        editor.teardownTimeObserver()

        editor.setupTimeObserver()
        clock.tick(to: 7)

        XCTAssertEqual(clock.liveObserverCount, 1)
        XCTAssertEqual(editor.currentPlaybackTime, 7, accuracy: 0.001)
    }

    func testStoppingTwiceIsHarmless() throws {
        let clock = FakePlaybackClock()
        let editor = try makeEditor(clock: clock)
        editor.setupTimeObserver()

        editor.teardownTimeObserver()
        editor.teardownTimeObserver()

        XCTAssertEqual(clock.liveObserverCount, 0)
    }
}
