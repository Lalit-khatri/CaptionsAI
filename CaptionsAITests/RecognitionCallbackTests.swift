@testable import CaptionsAI
import XCTest

/// How the recogniser's result handler is read, and how a double call is
/// kept from resuming the same continuation twice.
///
/// `String` stands in for `SFSpeechRecognitionResult`, which cannot be
/// constructed in a test. The decision does not depend on what the result is.
final class RecognitionCallbackTests: XCTestCase {
    private struct Dropped: Error, Equatable {}

    private enum Read: Equatable {
        case waiting
        case finished(String)
        case recognitionFailed(Dropped?)
        case noSpeechDetected
        case otherFailure(String)
    }

    private func read(_ result: String?, isFinal: Bool, error: Error?) -> Read {
        switch SpeechRecognizer.recognitionOutcome(result: result, isFinal: isFinal, error: error) {
        case .waiting:
            return .waiting
        case let .finished(value):
            return .finished(value)
        case let .failed(.recognitionFailed(underlying)):
            return .recognitionFailed(underlying as? Dropped)
        case .failed(.noSpeechDetected):
            return .noSpeechDetected
        case let .failed(other):
            return .otherFailure(other.localizedDescription)
        }
    }

    // MARK: - Recognition outcome

    func testAPartialResultKeepsWaiting() {
        XCTAssertEqual(read("hello", isFinal: false, error: nil), .waiting)
    }

    func testTheFinalResultFinishesWithThatResult() {
        XCTAssertEqual(read("hello world", isFinal: true, error: nil), .finished("hello world"))
    }

    func testAnErrorAloneFailsWithThatError() {
        XCTAssertEqual(read(nil, isFinal: false, error: Dropped()), .recognitionFailed(Dropped()))
    }

    /// The hang this fixed: a partial result alongside an error used to read
    /// as "keep waiting", and nothing else ever arrived.
    func testAnErrorWithAPartialResultFails() {
        XCTAssertEqual(read("hel", isFinal: false, error: Dropped()), .recognitionFailed(Dropped()))
    }

    /// Error first, as for compiler-synthesised continuations.
    func testAnErrorWithAFinalResultStillFails() {
        XCTAssertEqual(read("hello", isFinal: true, error: Dropped()), .recognitionFailed(Dropped()))
    }

    /// The recogniser breaking its contract must end the wait, not extend it.
    func testNoResultAndNoErrorFailsAsNoSpeech() {
        XCTAssertEqual(read(nil, isFinal: false, error: nil), .noSpeechDetected)
    }

    /// `isFinal` without a result is the same broken contract.
    func testFinalWithNoResultAndNoErrorFailsAsNoSpeech() {
        XCTAssertEqual(read(nil, isFinal: true, error: nil), .noSpeechDetected)
    }

    func testAnEmptyFinalTranscriptIsStillAFinishedResult() {
        // Empty is decided later, from the segments, as noSpeechDetected.
        XCTAssertEqual(read("", isFinal: true, error: nil), .finished(""))
    }

    // MARK: - Resume once

    func testOnlyTheFirstClaimSucceeds() {
        let once = ResumeOnce()

        XCTAssertEqual([once.claim(), once.claim(), once.claim()], [true, false, false])
    }

    func testEachGateIsIndependent() {
        let first = ResumeOnce()
        let second = ResumeOnce()

        XCTAssertTrue(first.claim())
        XCTAssertTrue(second.claim())
    }

    /// The handler can run on any queue. Exactly one of many racing claims
    /// may win, or the continuation is resumed twice and the app crashes.
    func testExactlyOneOfManyConcurrentClaimsSucceeds() {
        let once = ResumeOnce()
        let lock = NSLock()
        var wins = 0

        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if once.claim() {
                lock.withLock { wins += 1 }
            }
        }

        XCTAssertEqual(wins, 1)
    }
}
