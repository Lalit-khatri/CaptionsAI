@testable import CaptionsAI
import Speech
import SwiftUI
import UIKit
import XCTest

final class CaptionSegmentTests: XCTestCase {
    func testSegmentDuration() {
        let segment = CaptionSegment(startTime: 1.0, endTime: 3.5, text: "Hello world")
        XCTAssertEqual(segment.duration, 2.5, accuracy: 0.001)
    }

    func testFormattedTimeRange() {
        let segment = CaptionSegment(startTime: 72, endTime: 75, text: "Test")
        XCTAssertEqual(segment.formattedTimeRange, "1:12 - 1:15")
    }

    func testIsActive() {
        let segment = CaptionSegment(startTime: 5.0, endTime: 8.0, text: "Active test")

        XCTAssertFalse(segment.isActive(at: 4.9))
        XCTAssertTrue(segment.isActive(at: 5.0))
        XCTAssertTrue(segment.isActive(at: 6.5))
        XCTAssertFalse(segment.isActive(at: 8.0))
    }

    func testWordTimingEncoding() {
        let words = [
            WordTiming(word: "hello", startTime: 0.0, endTime: 0.5),
            WordTiming(word: "world", startTime: 0.5, endTime: 1.0),
        ]

        let segment = CaptionSegment(startTime: 0, endTime: 1, text: "hello world", words: words)

        XCTAssertEqual(segment.words.count, 2)
        XCTAssertEqual(segment.words[0].word, "hello")
        XCTAssertEqual(segment.words[1].word, "world")
    }

    func testActiveWord() {
        let words = [
            WordTiming(word: "this", startTime: 0.0, endTime: 0.3),
            WordTiming(word: "is", startTime: 0.3, endTime: 0.5),
            WordTiming(word: "great", startTime: 0.5, endTime: 1.0),
        ]

        let segment = CaptionSegment(startTime: 0, endTime: 1, text: "this is great", words: words)

        XCTAssertEqual(segment.activeWord(at: 0.1)?.word, "this")
        XCTAssertEqual(segment.activeWord(at: 0.4)?.word, "is")
        XCTAssertEqual(segment.activeWord(at: 0.7)?.word, "great")
        XCTAssertNil(segment.activeWord(at: 1.5))
    }
}

final class CaptionStyleTests: XCTestCase {
    /// The exact preset line-up. Asserted by name because the names are a
    /// product surface: a silent rename changes what users see in the style
    /// picker and orphans any project that persisted the old name.
    private static let expectedNames = [
        "Hormozi", "Beast", "Submagic", "Ali Abdaal", "Cyber Glow",
        "Karaoke", "Cinema", "Fire", "Vox Box", "Outline",
    ]

    func testPresetsCount() {
        XCTAssertEqual(CaptionStyle.presets.count, Self.expectedNames.count)
    }

    func testPresetNames() {
        XCTAssertEqual(CaptionStyle.presets.map(\.name), Self.expectedNames)
    }

    /// `CaptionStyle.id` is derived from `name`, so duplicate names would give
    /// two presets the same identity and break `ForEach` in the style picker.
    func testPresetIdentifiersAreUnique() {
        let ids = CaptionStyle.presets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate style ids: \(ids)")
    }

    func testWordByWordHighlightVariesByPreset() {
        // Karaoke is the word-by-word style; Cinema is deliberately not.
        XCTAssertTrue(CaptionStyle.karaoke.wordByWordHighlight)
        XCTAssertFalse(CaptionStyle.cinema.wordByWordHighlight)
        XCTAssertFalse(CaptionStyle.boldBox.wordByWordHighlight)
    }

    func testCodableColor() throws {
        let color = CodableColor("#FF0000")
        XCTAssertEqual(color.hex, "#FF0000")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(color)
        let decoded = try decoder.decode(CodableColor.self, from: data)

        XCTAssertEqual(decoded.hex, "#FF0000")
    }

    /// `Color.white` and `Color.black` live in a grayscale color space and
    /// expose two components, not four. `toHex()` used to index
    /// `components[2]` unconditionally, so converting either one trapped —
    /// a crash, not the `nil` its `-> String?` signature advertises.
    ///
    /// This was a characterization test asserting on component count, because
    /// calling `toHex()` would have torn down the whole bundle and hidden
    /// every other result. With the fix in it can assert the real thing.
    func testToHexHandlesGrayscaleColors() {
        XCTAssertEqual(CodableColor(Color.white).hex, "#FFFFFF")
        XCTAssertEqual(CodableColor(Color.black).hex, "#000000")
    }

    func testToHexHandlesRGBColors() {
        XCTAssertEqual(CodableColor(Color(red: 1, green: 0, blue: 0)).hex, "#FF0000")
        XCTAssertEqual(CodableColor(Color(red: 0, green: 1, blue: 0)).hex, "#00FF00")
    }
}

final class ExportPresetTests: XCTestCase {
    func testAllPresetsHaveDisplayNames() {
        for preset in ExportPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty)
            XCTAssertFalse(preset.iconName.isEmpty)
        }
    }

    func testInstagramReelsDisplayNameHasNoTrailingWhitespace() {
        let preset = ExportPreset.instagramReels
        XCTAssertEqual(preset.displayName, "Instagram Reels / TikTok / Shorts")
        XCTAssertFalse(preset.displayName.hasSuffix(" "))
    }

    func testInstagramReelsResolution() {
        let preset = ExportPreset.instagramReels
        XCTAssertEqual(preset.resolution, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(preset.aspectRatioString, "9:16")
    }

    func testYouTubeResolution() {
        let preset = ExportPreset.youtube
        XCTAssertEqual(preset.resolution, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(preset.aspectRatioString, "16:9")
    }

    func testOriginalPreset() {
        let preset = ExportPreset.original
        XCTAssertEqual(preset.resolution, .zero)
        XCTAssertEqual(preset.aspectRatioString, "Original")
    }
}

final class ProcessingViewTests: XCTestCase {
    func testWaveformBarHeightsAndDurationsAreDeterministic() {
        XCTAssertEqual(ProcessingView.barHeights.count, 20)
        XCTAssertEqual(ProcessingView.barDurations.count, 20)
        for height in ProcessingView.barHeights {
            XCTAssertGreaterThanOrEqual(height, 10)
            XCTAssertLessThanOrEqual(height, 60)
        }
        for duration in ProcessingView.barDurations {
            XCTAssertGreaterThanOrEqual(duration, 0.2)
            XCTAssertLessThanOrEqual(duration, 1.0)
        }
    }

    func testProcessingViewInitializesWithDuplicateWords() {
        let view = ProcessingView(
            progress: 0.5,
            words: ["the", "the", "cat", "sat", "the", "cat"],
            onCancel: {}
        )
        XCTAssertNotNil(view.body)
    }
}

final class CaptionDragTests: XCTestCase {
    func testCaptionDragClampsToBounds() {
        XCTAssertEqual(CaptionOverlay.clampYPosition(0.0), CaptionOverlay.minCaptionY)
        XCTAssertEqual(CaptionOverlay.clampYPosition(1.0), CaptionOverlay.maxCaptionY)
        XCTAssertEqual(CaptionOverlay.clampYPosition(-0.5), CaptionOverlay.minCaptionY)
        XCTAssertEqual(CaptionOverlay.clampYPosition(1.5), CaptionOverlay.maxCaptionY)
        XCTAssertEqual(CaptionOverlay.clampYPosition(0.5), 0.5)
    }

    func testCaptionOverlayInitializes() {
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        let vm = EditorViewModel(project: project)
        var y = 0.8
        let overlay = CaptionOverlay(
            viewModel: vm,
            currentTime: 0.0,
            yPosition: Binding(get: { y }, set: { y = $0 }),
            onPositionChanged: { y = $0 }
        )
        XCTAssertNotNil(overlay.body)
    }
}

final class SpeechRecognitionPrivacyTests: XCTestCase {
    func testRecognitionRequestRequiresOnDeviceWhenSupported() {
        let url = URL(fileURLWithPath: "/tmp/dummy.wav")
        let requestOnDevice = SpeechRecognizer.configureRecognitionRequest(for: url, supportsOnDevice: true)
        XCTAssertTrue(requestOnDevice.requiresOnDeviceRecognition)
        XCTAssertTrue(requestOnDevice.shouldReportPartialResults)
        XCTAssertEqual(requestOnDevice.taskHint, .dictation)

        let requestFallback = SpeechRecognizer.configureRecognitionRequest(for: url, supportsOnDevice: false)
        XCTAssertFalse(requestFallback.requiresOnDeviceRecognition)
    }
}

final class ImportStreamingTests: XCTestCase {
    func testMovieFileTransferRepresentation() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp4")
        let movie = MovieFile(url: tempURL)
        XCTAssertEqual(movie.url, tempURL)
    }
}





