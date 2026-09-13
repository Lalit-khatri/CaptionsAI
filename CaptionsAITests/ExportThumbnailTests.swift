@testable import CaptionsAI
import AVFoundation
import UIKit
import XCTest

final class ExportThumbnailTests: XCTestCase {

    func testAsynchronousThumbnailGenerationProducesValidImage() async throws {
        let videoURL = try await TestSupport.makeTestVideo(seconds: 1.0, size: CGSize(width: 320, height: 240))
        defer { TestSupport.remove(videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let (cgImage, time) = try await generator.image(at: .zero)
        let uiImage = UIImage(cgImage: cgImage)

        XCTAssertEqual(time, .zero)
        XCTAssertGreaterThan(uiImage.size.width, 0)
        XCTAssertGreaterThan(uiImage.size.height, 0)
        XCTAssertLessThanOrEqual(uiImage.size.width, 400)
        XCTAssertLessThanOrEqual(uiImage.size.height, 400)
    }
}
