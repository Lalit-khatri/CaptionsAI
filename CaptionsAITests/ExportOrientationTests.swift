@testable import CaptionsAI
import AVFoundation
import CoreImage
import UIKit
import XCTest

/// Whether a rotated source comes out the right way up, filling the frame.
///
/// The defect: orientation was decided twice, by two tests that disagreed.
/// `getVideoOrientation` matched four exact transforms and answered `.up` to
/// anything else; `resolveOriginalSize` asked `abs(b) == 1 && abs(c) == 1`.
/// On a front-camera transform such as `a=0, b=1, c=1, d=0` the second turned
/// the canvas portrait while the first declined to turn the frame — so a
/// landscape frame was letterboxed into a portrait video between two black
/// bars.
///
/// The compositor aspect-fits over black, so that mismatch is measurable: the
/// exported frame has black where the picture should be.
@MainActor
final class ExportOrientationTests: XCTestCase {
    /// A camera's 90° clockwise transform.
    private let quarterTurn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
    /// A reflected transform, as a front camera can record.
    private let mirroredQuarterTurn = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)

    // MARK: - One decision, read by both callers

    func testAnUprightTransformIsNotTurned() {
        XCTAssertEqual(ExportEngine.preferredOrientation(for: .identity), .up)
        XCTAssertFalse(ExportEngine.swapsDimensions(.identity))
    }

    func testAQuarterTurnIsTurnedAndSwapsTheDimensions() {
        XCTAssertEqual(ExportEngine.preferredOrientation(for: quarterTurn), .right)
        XCTAssertTrue(ExportEngine.swapsDimensions(quarterTurn))
    }

    func testTheOtherQuarterTurnGoesTheOtherWay() {
        let transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)

        XCTAssertEqual(ExportEngine.preferredOrientation(for: transform), .left)
        XCTAssertTrue(ExportEngine.swapsDimensions(transform))
    }

    func testAHalfTurnKeepsTheDimensions() {
        let transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)

        XCTAssertEqual(ExportEngine.preferredOrientation(for: transform), .down)
        XCTAssertFalse(ExportEngine.swapsDimensions(transform))
    }

    /// The transform the two detectors used to disagree about.
    func testAMirroredQuarterTurnIsStillAQuarterTurn() {
        XCTAssertEqual(ExportEngine.preferredOrientation(for: mirroredQuarterTurn), .right)
        XCTAssertTrue(ExportEngine.swapsDimensions(mirroredQuarterTurn))
    }

    /// Whatever the answer is for a given transform, the canvas and the pixels
    /// must reach it together. This is the property that was actually broken.
    func testTheCanvasAndThePixelsNeverDisagree() {
        let transforms = [
            CGAffineTransform.identity,
            quarterTurn,
            mirroredQuarterTurn,
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0),
            CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 0, ty: 0),
            CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0),
            CGAffineTransform(a: 0, b: 2, c: -2, d: 0, tx: 0, ty: 0),
        ]

        for transform in transforms {
            let turned = ExportEngine.preferredOrientation(for: transform)
            let quarter = turned == .left || turned == .right

            XCTAssertEqual(
                quarter, ExportEngine.swapsDimensions(transform),
                "\(transform): turned \(turned) but the canvas disagrees"
            )
        }
    }

    // MARK: - A real export of a rotated source

    /// The brightness of the exported frame, 0...255, at a point given as a
    /// fraction of the frame.
    ///
    /// Relative rather than absolute because the export preset scales the
    /// composition's render size up — a 240×320 canvas lands as 1080×1440.
    ///
    /// The fixture ramps black to white, so a late frame is bright everywhere
    /// it has picture. Black means the compositor put its background there.
    private func brightness(
        of url: URL, atX xFraction: CGFloat, y yFraction: CGFloat, time: Double
    ) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        let cgImage = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let x = min(max((width * xFraction).rounded(), 0), width - 1)
        let y = min(max((height * yFraction).rounded(), 0), height - 1)

        let context = CIContext()
        let bitmap = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { bitmap.deallocate() }

        context.render(
            CIImage(cgImage: cgImage),
            toBitmap: bitmap,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Int(bitmap[0])
    }

    private func exportRotated(by transform: CGAffineTransform) async throws -> (URL, CGSize) {
        let source = try await TestSupport.makeTestVideo(
            seconds: 1.0, size: CGSize(width: 320, height: 240), fps: 8, transform: transform
        )
        defer { TestSupport.remove(source) }

        let engine = ExportEngine()
        engine.photoLibrarySaver = { _ in }

        let output = try await engine.export(
            videoURL: source, settings: ExportSettings(), preset: .original,
            segments: [], style: .hormozi, captionYPosition: 0.8, addWatermark: false
        )

        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        return (output, size)
    }

    /// A 320×240 source turned a quarter is a 3:4 picture. Asserted as a ratio
    /// because the preset picks the pixel dimensions.
    private func assertPortraitAndFullFrame(
        _ output: URL, _ size: CGSize, line: UInt = #line
    ) async throws {
        XCTAssertEqual(size.width / size.height, 3.0 / 4.0, accuracy: 0.01, "the canvas", line: line)

        let middle = try await brightness(of: output, atX: 0.5, y: 0.5, time: 0.8)
        XCTAssertGreaterThan(middle, 64, "the frame has no picture in the middle", line: line)

        for edge in [0.02, 0.98] {
            let value = try await brightness(of: output, atX: 0.5, y: CGFloat(edge), time: 0.8)
            XCTAssertGreaterThan(
                value, 64,
                "a black bar at y=\(edge): the frame was not turned to match its canvas",
                line: line
            )
        }
    }

    /// The guard for deleting `compositionVideoTrack.preferredTransform`: an
    /// ordinary portrait recording still comes out portrait and full-frame.
    func testAQuarterTurnedSourceExportsPortraitWithNoBars() async throws {
        let (output, size) = try await exportRotated(by: quarterTurn)
        defer { TestSupport.remove(output) }

        try await assertPortraitAndFullFrame(output, size)
    }

    /// The one the old code got wrong.
    func testAMirroredQuarterTurnedSourceIsNotLetterboxed() async throws {
        let (output, size) = try await exportRotated(by: mirroredQuarterTurn)
        defer { TestSupport.remove(output) }

        try await assertPortraitAndFullFrame(output, size)
    }
}
