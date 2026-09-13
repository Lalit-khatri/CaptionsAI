@testable import CaptionsAI
import AVFoundation
import CoreGraphics
import Foundation
import SwiftData

/// Shared fixtures for the unit-test bundle.
///
/// Two seams live here, because both are awkward to reach from a test and both
/// are needed by most of the interesting assertions in this suite:
///
/// - ``makeInMemoryContainer()`` gives a real SwiftData stack that never
///   touches disk. That matters more than it sounds: several of this app's
///   worst defects are the gap between *what a view model is holding* and
///   *what is actually persisted*, and only a real store can tell those apart.
/// - ``makeTestVideo(seconds:size:fps:)`` encodes a genuinely decodable H.264
///   file. AVFoundation will not accept a hand-written stub, so any test that
///   touches an `AVAsset` needs a real one.
enum TestSupport {
    enum FixtureError: Error {
        case cannotAddInput
        case pixelBufferCreationFailed(CVReturn)
        case noCGContext
        case appendFailed(Error?)
        case writeFailed(Error?)
    }

    // MARK: - SwiftData

    /// An in-memory container over the app's real schema.
    ///
    /// Uses the same model list as `CaptionsAIApp`, so a schema change that
    /// breaks the app breaks these tests too — which is the point.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Project.self, CaptionSegment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Video fixtures

    /// A file that exists, for projects whose video is never actually decoded.
    ///
    /// ``Project/videoURL`` resolves through ``VideoLibrary`` and returns `nil`
    /// when the file is not on disk — that is the point of it, since a project
    /// whose video has gone must read as gone rather than as a URL pointing at
    /// nothing. Tests that fake the transcriber still need the file to be
    /// *there*, or the view model refuses with "Video file not found" before it
    /// ever reaches the seam under test.
    ///
    /// Not a decodable movie, deliberately: use ``makeTestVideo(seconds:size:fps:)``
    /// when AVFoundation has to open it. This is a few bytes and shared across
    /// the run.
    static let placeholderVideoURL: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("captionsai-placeholder.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data("placeholder".utf8))
        }
        return url
    }()

    /// Encodes a small, real H.264 movie and returns its URL.
    ///
    /// The caller owns the file; pair it with ``remove(_:)`` in a teardown
    /// block. Frames are a ramp from black to white so that a test can tell
    /// frames apart if it needs to.
    static func makeTestVideo(
        seconds: Double = 2.0,
        size: CGSize = CGSize(width: 640, height: 360),
        fps: Int32 = 30
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )

        guard writer.canAdd(input) else { throw FixtureError.cannotAddInput }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writeFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(Int(seconds * Double(fps)), 1)
        for frame in 0 ..< frameCount {
            let shade = Double(frame) / Double(max(frameCount - 1, 1))
            let buffer = try makePixelBuffer(size: size, shade: shade)

            // The writer is not real-time, but it still applies backpressure.
            // The status check is load-bearing: once the writer fails it stops
            // asking for data, so without it this loop never ends and the whole
            // test run hangs on a timeout rather than reporting the error.
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    throw FixtureError.writeFailed(writer.error)
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw FixtureError.appendFailed(writer.error)
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw FixtureError.writeFailed(writer.error)
        }
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func makePixelBuffer(size: CGSize, shade: Double) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey as String: true] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw FixtureError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw FixtureError.noCGContext
        }

        context.setFillColor(red: shade, green: shade, blue: shade, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
