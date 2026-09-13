@testable import CaptionsAI
import AVFoundation
import Foundation
import XCTest

final class AudioExtractionTests: XCTestCase {

    func testExtractAudioTrackFailsWhenVideoHasNoAudioTrack() async throws {
        let videoURL = try await TestSupport.makeTestVideo(seconds: 1.0)
        defer { TestSupport.remove(videoURL) }

        do {
            let extractedURL = try await SpeechRecognizer.extractAudioTrack(from: videoURL)
            defer { TestSupport.remove(extractedURL) }
            XCTFail("Expected extractAudioTrack to throw audioExtractionFailed for video without audio")
        } catch let error as SpeechError {
            guard case .audioExtractionFailed = error else {
                XCTFail("Expected SpeechError.audioExtractionFailed, got \(error)")
                return
            }
        }
    }

    func testExtractAudioTrackRejectsEmptyAudioTrackInsteadOfHandingBackHeaderOnlyWAV() async throws {
        let emptyMovieURL = try await TestSupport.makeTestMovieWithEmptyAudioTrack()
        defer { TestSupport.remove(emptyMovieURL) }

        do {
            let extractedURL = try await SpeechRecognizer.extractAudioTrack(from: emptyMovieURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: extractedURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            defer { TestSupport.remove(extractedURL) }
            XCTFail("Expected extractAudioTrack to fail on empty audio track, but returned a \(fileSize)-byte file at \(extractedURL)")
        } catch let error as SpeechError {
            guard case .audioExtractionFailed = error else {
                XCTFail("Expected SpeechError.audioExtractionFailed, got \(error)")
                return
            }
        }
    }

    func testExtractAudioTrackCleansUpTempFileWhenExtractionFails() async throws {
        let emptyMovieURL = try await TestSupport.makeTestMovieWithEmptyAudioTrack()
        defer { TestSupport.remove(emptyMovieURL) }

        let tmpDir = FileManager.default.temporaryDirectory
        let wavsBefore = Set((try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).filter { $0.hasSuffix(".wav") }) ?? [])

        do {
            _ = try await SpeechRecognizer.extractAudioTrack(from: emptyMovieURL)
            XCTFail("Expected extractAudioTrack to fail")
        } catch {
            // Expected
        }

        let wavsAfter = Set((try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).filter { $0.hasSuffix(".wav") }) ?? [])
        let leakedWavs = wavsAfter.subtracting(wavsBefore)
        XCTAssertTrue(leakedWavs.isEmpty, "Audio extraction leaked temporary WAV files: \(leakedWavs)")
    }
}
