@testable import CaptionsAI
import Foundation
import XCTest

final class AnalyticsServiceTests: XCTestCase {
    private final class MockAnalyticsProvider: AnalyticsProvider {
        struct RecordedEvent: Equatable {
            let name: String
            let parameters: [String: String]?
        }

        var recordedEvents: [RecordedEvent] = []

        func logEvent(_ name: String, parameters: [String: Any]?) {
            let stringified = parameters?.mapValues { "\($0)" }
            recordedEvents.append(RecordedEvent(name: name, parameters: stringified))
        }
    }

    private var mockProvider: MockAnalyticsProvider!

    override func setUp() {
        super.setUp()
        mockProvider = MockAnalyticsProvider()
        AnalyticsService.shared.provider = mockProvider
    }

    override func tearDown() {
        AnalyticsService.shared.provider = nil
        mockProvider = nil
        super.tearDown()
    }

    // MARK: - Event Tests

    func testVideoImportedLogsDuration() {
        AnalyticsService.videoImported(duration: 15.5)

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "video_imported")
        XCTAssertEqual(event?.parameters?["duration_seconds"], "15.5")
    }

    func testCaptionsGeneratedLogsWordCount() {
        AnalyticsService.captionsGenerated(wordCount: 42)

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "captions_generated")
        XCTAssertEqual(event?.parameters?["word_count"], "42")
    }

    func testExportCompletedLogsPresetAndProStatus() {
        AnalyticsService.exportCompleted(preset: "Shamani", isPro: true)

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "export_completed")
        XCTAssertEqual(event?.parameters?["preset"], "Shamani")
        XCTAssertEqual(event?.parameters?["is_pro"], "true")
    }

    func testExportCompletedForFreeUser() {
        AnalyticsService.exportCompleted(preset: "Hormozi", isPro: false)

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "export_completed")
        XCTAssertEqual(event?.parameters?["preset"], "Hormozi")
        XCTAssertEqual(event?.parameters?["is_pro"], "false")
    }

    func testPaywallShownLogsTrigger() {
        AnalyticsService.paywallShown(trigger: "watermark_removal")

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "paywall_shown")
        XCTAssertEqual(event?.parameters?["trigger"], "watermark_removal")
    }

    func testPurchaseCompletedLogsProductID() {
        AnalyticsService.purchaseCompleted(productID: "com.lalitkhatri.CaptionsAI.yearly")

        XCTAssertEqual(mockProvider.recordedEvents.count, 1)
        let event = mockProvider.recordedEvents.first
        XCTAssertEqual(event?.name, "purchase_completed")
        XCTAssertEqual(event?.parameters?["product_id"], "com.lalitkhatri.CaptionsAI.yearly")
    }

    func testNoOpWhenProviderIsNil() {
        AnalyticsService.shared.provider = nil

        AnalyticsService.videoImported(duration: 10.0)
        AnalyticsService.captionsGenerated(wordCount: 5)
        AnalyticsService.exportCompleted(preset: "Cinema", isPro: false)
        AnalyticsService.paywallShown(trigger: "style_picker")
        AnalyticsService.purchaseCompleted(productID: "test_product")

        XCTAssertTrue(mockProvider.recordedEvents.isEmpty)
    }
}
