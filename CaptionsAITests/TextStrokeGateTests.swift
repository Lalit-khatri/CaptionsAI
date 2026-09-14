@testable import CaptionsAI
import UIKit
import XCTest

/// The gate on outlined caption styles.
///
/// Three of the proposed new presets are outlined text, which means adding
/// `.strokeWidth` to the export renderer's attribute dictionaries. That is only
/// safe if two things hold, and neither is obvious:
///
/// 1. A stroke must not move a wrap point. `drawText` measures with
///    `boundingRect` and then draws into a rect derived from that measurement.
///    If the stroke changed the measurement, every caption in the app would
///    re-wrap and existing projects would export differently.
/// 2. `.strokeWidth` must be relative to the point size, not an absolute width.
///    The export renders at up to 4x the preview and multiplies absolute
///    lengths by a `scaleFactor`; a relative one multiplied as well would come
///    out four times too thick. This is not hypothetical — the deliberation
///    that produced these presets contained a draft that wrote
///    `-width * scaleFactor`.
///
/// These tests run before any stroke exists. If they fail, the outlined presets
/// do not ship.
@MainActor
final class TextStrokeGateTests: XCTestCase {
    private let maxWidth: CGFloat = 800

    private func attributes(font: UIFont, stroke: CGFloat?) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        if let stroke {
            attrs[.strokeWidth] = stroke
            attrs[.strokeColor] = UIColor.black
        }
        return attrs
    }

    /// Measured exactly as `CaptionRenderer.drawText` measures.
    private func boundingRect(_ text: String, font: UIFont, stroke: CGFloat?) -> CGRect {
        NSAttributedString(string: text, attributes: attributes(font: font, stroke: stroke))
            .boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
    }

    private func inkBounds(_ text: String, font: UIFont, stroke: CGFloat?) throws -> CGRect {
        let size = CGSize(width: 900, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            NSAttributedString(string: text, attributes: attributes(font: font, stroke: stroke))
                .draw(at: CGPoint(x: 100, y: 100))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        return try XCTUnwrap(CaptionInk.bounds(of: cgImage))
    }

    // MARK: - 1. A stroke does not move a wrap point

    func testStrokeDoesNotChangeTheMeasuredSizeOfASingleLine() {
        for size in [24, 34, 48, 72] as [CGFloat] {
            let font = UIFont.systemFont(ofSize: size, weight: .black)

            XCTAssertEqual(
                boundingRect("VIRAL", font: font, stroke: nil),
                boundingRect("VIRAL", font: font, stroke: -7),
                "a stroke changed the measured size at \(size)pt"
            )
        }
    }

    /// The case that actually matters: text long enough to wrap. Equal heights
    /// mean the same number of lines, equal widths mean the same break points.
    func testStrokeDoesNotChangeWhereALongCaptionWraps() {
        let text = "THIS CAPTION IS LONG ENOUGH THAT IT HAS TO WRAP ONTO SEVERAL LINES"

        for size in [34, 56] as [CGFloat] {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            let plain = boundingRect(text, font: font, stroke: nil)
            let stroked = boundingRect(text, font: font, stroke: -7)

            XCTAssertGreaterThan(plain.height, font.lineHeight * 1.5, "precondition: it wrapped")
            XCTAssertEqual(plain, stroked, "a stroke moved a wrap point at \(size)pt")
        }
    }

    /// Also true of the sign we do not use, so the invariance is a property of
    /// `.strokeWidth` and not a coincidence of one value.
    func testNeitherSignOfStrokeChangesTheMeasurement() {
        let font = UIFont.systemFont(ofSize: 40, weight: .black)

        XCTAssertEqual(boundingRect("OUTLINE", font: font, stroke: nil),
                       boundingRect("OUTLINE", font: font, stroke: 7))
        XCTAssertEqual(boundingRect("OUTLINE", font: font, stroke: nil),
                       boundingRect("OUTLINE", font: font, stroke: -7))
    }

    // MARK: - 2. The stroke is relative to the point size

    /// Doubling the point size must double the stroke. If `.strokeWidth` were
    /// an absolute point width the extra ink would be identical at both sizes,
    /// and the ratio below would come out near 1.
    func testTheStrokeGrowsWithTheFontRatherThanStayingAFixedWidth() throws {
        let small = try strokeThickness(pointSize: 40)
        let large = try strokeThickness(pointSize: 80)

        XCTAssertGreaterThan(small, 1, "no measurable stroke at 40pt")
        XCTAssertEqual(
            large / small, 2, accuracy: 0.45,
            "stroke thickness did not double with the point size: \(small) -> \(large)"
        )
    }

    /// Extra ink on each side, in points, from a -7 stroke at the given size.
    private func strokeThickness(pointSize: CGFloat) throws -> CGFloat {
        let font = UIFont.systemFont(ofSize: pointSize, weight: .black)
        let plain = try inkBounds("H", font: font, stroke: nil)
        let stroked = try inkBounds("H", font: font, stroke: -7)

        return (stroked.width - plain.width) / 2
    }

    /// And the consequence, stated plainly: because it is relative, the export
    /// must pass the same number the preview passes. Multiplying by the render
    /// scale factor is the bug this gate exists to prevent.
    func testScalingTheStrokeByTheRenderFactorWouldBeWrong() throws {
        let font = UIFont.systemFont(ofSize: 40, weight: .black)
        let correct = try inkBounds("H", font: font, stroke: -7)
        let scaledAsIfAbsolute = try inkBounds("H", font: font, stroke: -7 * 4)

        XCTAssertGreaterThan(
            scaledAsIfAbsolute.width, correct.width + 4,
            "multiplying strokeWidth by a 4x scale factor is visibly wrong, as expected"
        )
    }

    // MARK: - The sign we want

    /// Positive is stroke-only — hollow letters. Negative fills and strokes.
    /// The presets want negative; getting this backwards produces text with no
    /// interior, which is legible on a still and invisible over video.
    func testANegativeStrokeKeepsTheLetterFilled() throws {
        let font = UIFont.systemFont(ofSize: 64, weight: .black)

        XCTAssertNotEqual(
            try opaquePixels("H", font: font, stroke: 7),
            try opaquePixels("H", font: font, stroke: -7),
            "hollow and filled strokes drew the same pixels"
        )
        XCTAssertGreaterThan(
            try opaquePixels("H", font: font, stroke: -7),
            try opaquePixels("H", font: font, stroke: 7),
            "the filled stroke drew less ink than the hollow one"
        )
    }

    private func opaquePixels(_ text: String, font: UIFont, stroke: CGFloat?) throws -> Int {
        let size = CGSize(width: 300, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            NSAttributedString(string: text, attributes: attributes(font: font, stroke: stroke))
                .draw(at: CGPoint(x: 40, y: 40))
        }
        let cgImage = try XCTUnwrap(image.cgImage)

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (0 ..< width * height).count { pixels[$0 * 4 + 3] > 16 }
    }
}
