import XCTest
@testable import CaptionsAI

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
            WordTiming(word: "world", startTime: 0.5, endTime: 1.0)
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
            WordTiming(word: "great", startTime: 0.5, endTime: 1.0)
        ]
        
        let segment = CaptionSegment(startTime: 0, endTime: 1, text: "this is great", words: words)
        
        XCTAssertEqual(segment.activeWord(at: 0.1)?.word, "this")
        XCTAssertEqual(segment.activeWord(at: 0.4)?.word, "is")
        XCTAssertEqual(segment.activeWord(at: 0.7)?.word, "great")
        XCTAssertNil(segment.activeWord(at: 1.5))
    }
}

final class CaptionStyleTests: XCTestCase {
    
    func testPresetsCount() {
        XCTAssertEqual(CaptionStyle.presets.count, 8)
    }
    
    func testPresetNames() {
        let names = CaptionStyle.presets.map(\.name)
        XCTAssertTrue(names.contains("Clean"))
        XCTAssertTrue(names.contains("Bold"))
        XCTAssertTrue(names.contains("Neon"))
        XCTAssertTrue(names.contains("Minimal"))
        XCTAssertTrue(names.contains("Highlight"))
        XCTAssertTrue(names.contains("Typewriter"))
        XCTAssertTrue(names.contains("Subtitle"))
        XCTAssertTrue(names.contains("Pop"))
    }
    
    func testHighlightStyleHasWordByWord() {
        XCTAssertTrue(CaptionStyle.highlight.wordByWordHighlight)
        XCTAssertFalse(CaptionStyle.clean.wordByWordHighlight)
    }
    
    func testCodableColor() {
        let color = CodableColor("#FF0000")
        XCTAssertEqual(color.hex, "#FF0000")
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try! encoder.encode(color)
        let decoded = try! decoder.decode(CodableColor.self, from: data)
        
        XCTAssertEqual(decoded.hex, "#FF0000")
    }
}

final class ExportPresetTests: XCTestCase {
    
    func testAllPresetsHaveDisplayNames() {
        for preset in ExportPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty)
            XCTAssertFalse(preset.iconName.isEmpty)
        }
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
