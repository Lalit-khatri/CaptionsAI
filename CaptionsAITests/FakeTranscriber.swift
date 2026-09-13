@testable import CaptionsAI
import Foundation
import XCTest

/// A `Transcribing` stand-in that lets a test decide when — and whether —
/// transcription finishes.
///
/// The interesting behaviours here are the two that block. The real
/// `SFSpeechRecognitionTask` callback can fire *after* the user has cancelled,
/// and what the app does with that late delivery is the difference between a
/// harmless no-op and deleting the user's edited captions from the store.
final class FakeTranscriber: Transcribing {
    enum Behaviour {
        /// Returns straight away.
        case succeed([CaptionSegment])
        /// Throws straight away.
        case fail(Error)
        /// Blocks until the calling task is cancelled, then throws — a run
        /// that never produces anything.
        case hangUntilCancelled
        /// Blocks until cancelled and then **succeeds anyway**, modelling the
        /// recognizer callback that arrives after the user walked away.
        case deliverAfterCancellation([CaptionSegment])
    }

    var behaviour: Behaviour = .succeed([])
    var isAuthorized = true

    var progress: Double = 0
    var partialResults: [String] = []

    private(set) var recognizeCallCount = 0
    private(set) var authorizationCallCount = 0
    private(set) var sawCancellation = false

    func requestAuthorization() async -> Bool {
        authorizationCallCount += 1
        return isAuthorized
    }

    func recognizeSpeech(from _: URL) async throws -> [CaptionSegment] {
        recognizeCallCount += 1
        switch behaviour {
        case let .succeed(segments):
            return segments
        case let .fail(error):
            throw error
        case .hangUntilCancelled:
            await waitForCancellation()
            throw CancellationError()
        case let .deliverAfterCancellation(segments):
            await waitForCancellation()
            return segments
        }
    }

    private func waitForCancellation() async {
        while !Task.isCancelled {
            // Sleep throws on cancellation; the loop condition is the real
            // exit, the sleep just keeps this from spinning a core.
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        sawCancellation = true
    }
}

// MARK: - Polling

/// Waits for a condition to become true, or fails the test.
///
/// Needed because the interesting transitions here are driven by a detached
/// task rather than by the call under test returning.
func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2.0,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTFail("timed out waiting for: \(description)", file: file, line: line)
}
