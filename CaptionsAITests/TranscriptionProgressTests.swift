@testable import CaptionsAI
import XCTest

/// Whether the transcription progress ring actually moves.
///
/// The defect: the fraction was `0.3 + 0.6 * words.count / max(words.count, 1)`
/// — a ratio of a number to itself. It came out at 0.9 for any non-empty
/// result, so the ring jumped to 90% on the first recognised word and sat
/// there for the whole of the longest stage of the job. On a long video that
/// reads as a hang, and the Cancel button starts looking attractive.
final class TranscriptionProgressTests: XCTestCase {
    private let clip: Double = 60

    // MARK: - It moves

    func testProgressAdvancesAsMoreOfTheClipIsHeard() {
        let quarter = SpeechRecognizer.recognitionProgress(heard: 15, of: clip)
        let half = SpeechRecognizer.recognitionProgress(heard: 30, of: clip)
        let threeQuarters = SpeechRecognizer.recognitionProgress(heard: 45, of: clip)

        XCTAssertLessThan(quarter, half, "a quarter of the clip reads the same as half of it")
        XCTAssertLessThan(half, threeQuarters, "half the clip reads the same as three quarters")
    }

    func testHalfTheClipSitsHalfwayThroughTheStage() {
        let expected = (kProgressAudioExtracted + kProgressTranscribed) / 2

        XCTAssertEqual(SpeechRecognizer.recognitionProgress(heard: 30, of: clip), expected, accuracy: 0.001)
    }

    func testEverySecondOfALongClipIsDistinguishable() {
        // A ten minute clip: the ring should not be quantised into two states.
        let readings = stride(from: 0.0, through: 600.0, by: 60.0)
            .map { SpeechRecognizer.recognitionProgress(heard: $0, of: 600) }

        XCTAssertEqual(Set(readings).count, readings.count, "the progress ring only has \(Set(readings).count) distinct positions")
    }

    // MARK: - It stays inside its stage

    func testNothingHeardYetLeavesTheRingWhereExtractionFinished() {
        XCTAssertEqual(SpeechRecognizer.recognitionProgress(heard: 0, of: clip), kProgressAudioExtracted)
    }

    func testHearingTheWholeClipHandsOverToGrouping() {
        XCTAssertEqual(SpeechRecognizer.recognitionProgress(heard: clip, of: clip), kProgressTranscribed)
    }

    func testATimestampPastTheEndOfTheClipDoesNotOvershoot() {
        // Recognised timestamps can run past the asset's reported duration.
        XCTAssertEqual(SpeechRecognizer.recognitionProgress(heard: clip + 30, of: clip), kProgressTranscribed)
    }

    func testTheRingNeverRunsPastTheHandover() {
        // Grouping then sets the ring to exactly the handover value, so any
        // overshoot here — including a floating point hair — is a step back.
        for heard in stride(from: 0.0, through: clip * 2, by: 7) {
            XCTAssertLessThanOrEqual(
                SpeechRecognizer.recognitionProgress(heard: heard, of: clip),
                kProgressTranscribed
            )
        }
    }

    func testProgressNeverRunsBackwards() {
        var previous = 0.0
        for second in stride(from: 0.0, through: clip, by: 0.5) {
            let now = SpeechRecognizer.recognitionProgress(heard: second, of: clip)
            XCTAssertGreaterThanOrEqual(now, previous)
            previous = now
        }
    }

    // MARK: - Degenerate clips

    func testAClipOfUnknownLengthDoesNotProduceNaN() {
        let reading = SpeechRecognizer.recognitionProgress(heard: 12, of: 0)

        XCTAssertFalse(reading.isNaN, "a NaN here reaches a ProgressView")
        XCTAssertEqual(reading, kProgressAudioExtracted)
    }
}
