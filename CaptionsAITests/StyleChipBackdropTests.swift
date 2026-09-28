@testable import CaptionsAI
import SwiftUI
import XCTest

/// The frame of the user's video drawn behind every style chip.
@MainActor
final class StyleChipBackdropTests: XCTestCase {
    private func video(seconds: Double = 2, size: CGSize, transform: CGAffineTransform = .identity) async throws -> URL {
        let url = try await TestSupport.makeTestVideo(seconds: seconds, size: size, transform: transform)
        addTeardownBlock { TestSupport.remove(url) }
        return url
    }

    // MARK: - Reading the frame

    func testNoVideoMeansNoBackdrop() async {
        let image = await StyleSheetView.backdropFrame(from: nil, at: 0)
        XCTAssertNil(image)
    }

    func testAFileThatWillNotDecodeMeansNoBackdrop() async {
        let image = await StyleSheetView.backdropFrame(from: TestSupport.placeholderVideoURL, at: 0)
        XCTAssertNil(image)
    }

    func testALandscapeFrameIsScaledDownToTheMaximumKeepingItsShape() async throws {
        let url = try await video(size: CGSize(width: 640, height: 360))
        let frame = await StyleSheetView.backdropFrame(from: url, at: 1)
        let image = try XCTUnwrap(frame)
        XCTAssertEqual(image.size.width, 480, accuracy: 1)
        XCTAssertEqual(image.size.height, 270, accuracy: 1)
    }

    func testAPortraitPhoneVideoComesOutUpright() async throws {
        // Stored 640x360 with a quarter turn, as an iPhone records portrait.
        let url = try await video(
            size: CGSize(width: 640, height: 360),
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        )
        let frame = await StyleSheetView.backdropFrame(from: url, at: 1)
        let image = try XCTUnwrap(frame)
        XCTAssertEqual(image.size.width, 270, accuracy: 1)
        XCTAssertEqual(image.size.height, 480, accuracy: 1)
    }

    func testAPlayheadPastTheEndStillGivesAFrame() async throws {
        let url = try await video(seconds: 1, size: CGSize(width: 320, height: 180))
        let image = await StyleSheetView.backdropFrame(from: url, at: 60)
        XCTAssertEqual(try XCTUnwrap(image).size.width, 320, accuracy: 1)
    }

    // MARK: - Drawing it

    private func renderedSize(backdrop: UIImage?) throws -> CGSize {
        let renderer = ImageRenderer(
            content: StylePreviewCard(style: .hormozi, isSelected: false, previewText: "Check out this caption", backdrop: backdrop)
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "the chip did not render").size
    }

    func testATallFrameCropsToTheChipInsteadOfGrowingIt() throws {
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 1600)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 90, height: 1600))
        }
        XCTAssertEqual(try renderedSize(backdrop: tall), try renderedSize(backdrop: nil))
    }

    func testTheBackdropIsDrawnOnThePlate() throws {
        let red = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        }
        let renderer = ImageRenderer(
            content: StylePreviewCard(style: .hormozi, isSelected: false, previewText: "Hi", backdrop: red)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        // A corner of the plate, clear of the sample text and the border:
        // red under a 35% black dim is about (166, 0, 0).
        let pixel = try XCTUnwrap(Self.rgb(of: image, x: 12, y: 12))
        XCTAssertEqual(Double(pixel.red), 166, accuracy: 12)
        XCTAssertLessThan(pixel.green, 20)
        XCTAssertLessThan(pixel.blue, 20)
    }

    private static func rgb(of image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }
}
