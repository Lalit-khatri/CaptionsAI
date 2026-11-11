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
        /// Never returns, never throws, ignores cancellation — a complete hang.
        case hangIndefinitely
    }

    var behaviour: Behaviour = .succeed([])
    var isAuthorized = true

    var progress: Double = 0
    var partialResults: [String] = []

    private(set) var recognizeCallCount = 0
    private(set) var authorizationCallCount = 0
    private(set) var sawCancellation = false

    /// How long `prepare()` takes, standing in for a model download.
    var prepareDuration: TimeInterval = 0
    /// Thrown by `prepare()` once `prepareDuration` has passed.
    var prepareError: Error?
    private(set) var prepareCallCount = 0
    /// What the run reports it detected, as auto-detect would.
    var detection: LanguageDetection?

    func requestAuthorization() async -> Bool {
        authorizationCallCount += 1
        return isAuthorized
    }

    func prepare() async throws {
        prepareCallCount += 1
        if prepareDuration > 0 {
            try await Task.sleep(nanoseconds: UInt64(prepareDuration * 1_000_000_000))
        }
        if let prepareError { throw prepareError }
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
        case .hangIndefinitely:
            // Park, like a recognizer whose callback never fires. A
            // `while true { try? await Task.sleep }` loop spins at 100% CPU
            // once withDeadline cancels it — cancelled sleeps return
            // immediately and `try?` swallows the error — and each leaked
            // task then holds a cooperative-pool thread for the rest of
            // the run.
            await parkForever()
            throw CancellationError()
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

/// Suspends forever without holding a thread: the continuation is never
/// resumed, and the unsafe variant does not log a leak.
func parkForever() async {
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
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

/// Gives already-scheduled work time to run before asserting that something
/// did **not** happen.
///
/// `waitUntil` can only wait for a condition to become true. Asserting a
/// negative — "the cancelled run did not clear the flag" — needs the opposite:
/// let everything in flight finish, then look.
func settle(turns: Int = 50) async {
    try? await Task.sleep(nanoseconds: 50_000_000)
    for _ in 0 ..< turns {
        await Task.yield()
    }
}
