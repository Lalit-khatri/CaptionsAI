@testable import CaptionsAI
import AVFoundation
import Foundation
import XCTest

/// Play, pause, and what happens to playback when the editor goes away.
@MainActor
final class EditorPlaybackTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func editorWithVideo() throws -> EditorViewModel {
        let reference = try VideoLibrary.store(data: Data("video".utf8))
        let url = try XCTUnwrap(VideoLibrary.resolve(reference))
        written.append(url)
        return EditorViewModel(
            project: Project(name: "Here", videoURL: url),
            speechRecognizer: FakeTranscriber(),
            audioSession: FakeAudioSession()
        )
    }

    private func editorWithoutVideo() -> EditorViewModel {
        EditorViewModel(
            project: Project(
                name: "Gone",
                videoURL: URL(fileURLWithPath: "/tmp/captionsai-absent-\(UUID().uuidString).mov")
            ),
            speechRecognizer: FakeTranscriber(),
            audioSession: FakeAudioSession()
        )
    }

    // MARK: - Toggle

    func testTogglingFromPausedPlays() throws {
        let editor = try editorWithVideo()

        editor.togglePlayPause()

        XCTAssertTrue(editor.isPlaying)
    }

    func testTogglingTwiceIsPausedAgainWithThePlayerStopped() throws {
        let editor = try editorWithVideo()

        editor.togglePlayPause()
        editor.togglePlayPause()

        XCTAssertFalse(editor.isPlaying)
        XCTAssertEqual(editor.player?.rate, 0)
    }

    /// With no video there is nothing to play, and the button must not claim
    /// otherwise by flipping to "Pause".
    func testTogglingWithoutAVideoStaysPaused() {
        let editor = editorWithoutVideo()

        editor.togglePlayPause()

        XCTAssertFalse(editor.isPlaying)
    }

    // MARK: - Leaving the editor

    /// The defect: Export or Preview pushed over a playing editor, and its
    /// audio kept going underneath.
    func testPausingWhilePlayingStopsThePlayer() throws {
        let editor = try editorWithVideo()
        editor.togglePlayPause()

        editor.pausePlayback()

        XCTAssertFalse(editor.isPlaying)
        XCTAssertEqual(editor.player?.rate, 0)
    }

    func testPausingWhilePausedStaysPaused() throws {
        let editor = try editorWithVideo()

        editor.pausePlayback()

        XCTAssertFalse(editor.isPlaying)
        XCTAssertEqual(editor.player?.rate, 0)
    }

    /// Coming back after a pause, one tap plays again rather than needing
    /// two to get past a stale "playing" flag.
    func testOneTapPlaysAgainAfterLeavingMidPlayback() throws {
        let editor = try editorWithVideo()
        editor.togglePlayPause()
        editor.pausePlayback()

        editor.togglePlayPause()

        XCTAssertTrue(editor.isPlaying)
    }

    func testPausingWithoutAVideoIsHarmless() {
        let editor = editorWithoutVideo()

        editor.pausePlayback()

        XCTAssertFalse(editor.isPlaying)
        XCTAssertNil(editor.player)
    }
}
