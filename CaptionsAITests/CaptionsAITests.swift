@testable import CaptionsAI
import AVFoundation
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

/// What the Quality picker actually changes.
///
/// The defect: the codec preset was tried first, and `.h264` maps to
/// `AVAssetExportPresetHighestQuality`, which is always compatible. It
/// therefore always won the candidate race, so Medium / High / Maximum
/// produced byte-identical encoder settings while the UI reported a
/// difference and the estimate quoted three different file sizes.
final class ExportQualityTests: XCTestCase {
    func testEveryOfferedTierProducesADifferentEncoderPreset() {
        for codec in ExportCodec.allCases {
            let presets = ExportQuality.allCases.map { $0.exportPreset(for: codec) }
            XCTAssertEqual(
                Set(presets).count, presets.count,
                "\(codec.rawValue) offers tiers that encode identically: \(presets)"
            )
        }
    }

    /// `.high` used to map to `AVAssetExportPreset1920x1080`, a *resolution*
    /// preset that silently clamps a 4K render down to 1080p. A quality tier
    /// must not overrule the resolution the user picked.
    func testAQualityTierNeverCarriesAResolutionCeilingForH264() {
        let clamping = [
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPreset3840x2160,
        ]
        for quality in ExportQuality.allCases {
            XCTAssertFalse(
                clamping.contains(quality.exportPreset(for: .h264)),
                "\(quality.rawValue) clamps the output resolution"
            )
        }
    }

    func testTheCodecDecidesThePresetFamily() {
        XCTAssertEqual(ExportQuality.high.exportPreset(for: .h264), AVAssetExportPresetHighestQuality)
        XCTAssertEqual(ExportQuality.high.exportPreset(for: .h265), AVAssetExportPresetHEVCHighestQuality)
    }

    /// The estimate is only honest if it moves with the thing it is estimating.
    func testTheEstimateStillSeparatesTheTiers() {
        var settings = ExportSettings()
        settings.resolution = .full1080
        settings.codec = .h264

        let sizes = ExportQuality.allCases.map { quality -> String in
            settings.quality = quality
            return settings.estimatedFileSize(durationSeconds: 60)
        }
        XCTAssertEqual(Set(sizes).count, sizes.count, "two tiers quote the same size: \(sizes)")
    }
}

/// What the paywall's only button does when there is nothing to buy.
///
/// The defect: the CTA body was `if let product { … }` with no `else`. When
/// `Product.products(for:)` had failed — no network, a sandbox account not
/// signed in, product IDs not yet approved — `monthlyProduct` and
/// `yearlyProduct` are both nil, so tapping "Start Free Trial" ran an empty
/// closure. No purchase, no spinner, no message. `storeKit.error` was
/// assigned by `loadProducts()` and read by nobody, and `isLoading` likewise,
/// so the screen could not even say it was still trying.
final class PaywallCTATests: XCTestCase {
    func testTheButtonSaysItIsWorkingWhileProductsAreLoading() {
        XCTAssertEqual(
            PaywallView.ctaState(isLoading: true, hasProduct: false, error: nil),
            .loading
        )
    }

    /// The load failed and said why. The reason belongs on screen, not in a
    /// property nothing reads.
    func testAFailedLoadSurfacesTheReason() {
        let state = PaywallView.ctaState(
            isLoading: false,
            hasProduct: false,
            error: "Failed to load products: offline"
        )
        XCTAssertEqual(state, .unavailable("Failed to load products: offline"))
    }

    /// No product and no error is still a dead button, so it still has to say
    /// something rather than silently doing nothing.
    func testAMissingProductWithNoErrorStillExplainsItself() {
        guard case let .unavailable(message) = PaywallView.ctaState(
            isLoading: false, hasProduct: false, error: nil
        ) else {
            return XCTFail("a tappable button with nothing to buy must explain itself")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testTheButtonIsOnlyBuyableWhenThereIsSomethingToBuy() {
        XCTAssertEqual(
            PaywallView.ctaState(isLoading: false, hasProduct: true, error: nil),
            .ready
        )
        XCTAssertTrue(PaywallView.ctaState(isLoading: false, hasProduct: true, error: nil).isPurchasable)
        XCTAssertFalse(PaywallView.ctaState(isLoading: true, hasProduct: false, error: nil).isPurchasable)
        XCTAssertFalse(PaywallView.ctaState(isLoading: false, hasProduct: false, error: nil).isPurchasable)
    }

    /// The comparison table advertised "All 10+" against exactly ten presets.
    /// Deriving the number means the copy cannot drift from the product again.
    func testTheStyleCountClaimMatchesTheStylesThatExist() {
        XCTAssertEqual(PaywallView.proStyleCountText, "All 10")
        XCTAssertEqual(PaywallView.proStyleCountText, "All \(CaptionStyle.presets.count)")
        XCTAssertFalse(PaywallView.proStyleCountText.contains("+"))
    }
}








// MARK: - Export Size Estimate

/// The export sheet quotes a file size before the user commits to a render.
/// The quote scaled bitrate by resolution *tier* rather than by pixels, so a 4K
/// export was advertised at roughly half its real size — the user picked 4K on
/// the strength of "~75 MB" and got a file twice that. The audio track was
/// missing from the arithmetic entirely, so muting a clip changed nothing.
final class ExportSizeEstimateTests: XCTestCase {
    private func settings(
        _ resolution: ExportResolution,
        audio: Bool = true
    ) -> ExportSettings {
        var s = ExportSettings()
        s.resolution = resolution
        s.quality = .high
        s.codec = .h264
        s.includeAudio = audio
        return s
    }

    /// 4K carries four times the pixels of 1080p, so it must quote roughly four
    /// times the size. It used to quote two.
    func testFourKIsQuotedAtFourTimesTenEightyNotTwice() {
        XCTAssertEqual(settings(.full1080).estimatedFileSize(durationSeconds: 60), "~38 MB")
        XCTAssertEqual(settings(.uhd4K).estimatedFileSize(durationSeconds: 60), "~151 MB")
    }

    /// 720p is 44% of 1080p's pixels, not 67%.
    func testSevenTwentyIsQuotedByPixelsNotByLineCount() {
        XCTAssertEqual(settings(.hd720).estimatedFileSize(durationSeconds: 60), "~18 MB")
    }

    /// Dropping the audio track makes the file smaller, so the quote must move.
    func testMutingTheExportLowersTheQuote() {
        let withAudio = settings(.uhd4K).estimatedFileSize(durationSeconds: 60)
        let silent = settings(.uhd4K, audio: false).estimatedFileSize(durationSeconds: 60)
        XCTAssertNotEqual(withAudio, silent)
        XCTAssertEqual(silent, "~150 MB")
    }
}

// MARK: - Paywall Prices

/// The paywall printed "$2.99" and "$14.99" whenever the real products had not
/// arrived, and a "SAVE 58%" badge computed by hand from those same two
/// invented numbers. A user in Tokyo or Berlin was quoted dollars they would
/// never be charged, and the saving was asserted regardless of what the two
/// plans actually cost in their storefront.
final class PaywallPriceTests: XCTestCase {
    /// A price we do not know is not a price we may guess at.
    func testAnUnknownPriceIsNotInventedInDollars() {
        let text = PaywallView.priceText(displayPrice: nil)
        XCTAssertFalse(text.contains("$"))
        XCTAssertNotEqual(text, "$2.99")
        XCTAssertNotEqual(text, "$14.99")
        XCTAssertFalse(text.isEmpty)
    }

    /// StoreKit already formats for the storefront's currency and locale, so
    /// the string is passed through untouched.
    func testTheStoresOwnPriceStringIsShownVerbatim() {
        XCTAssertEqual(PaywallView.priceText(displayPrice: "¥480"), "¥480")
        XCTAssertEqual(PaywallView.priceText(displayPrice: "2,99 €"), "2,99 €")
    }

    /// No prices means no claim about savings.
    func testTheSavingsBadgeIsAbsentWhenPricesAreUnknown() {
        XCTAssertNil(PaywallView.savingsBadge(monthlyPrice: nil, yearlyPrice: nil))
        XCTAssertNil(PaywallView.savingsBadge(monthlyPrice: 2.99, yearlyPrice: nil))
        XCTAssertNil(PaywallView.savingsBadge(monthlyPrice: nil, yearlyPrice: 14.99))
    }

    /// The badge is arithmetic on the real prices, not a number typed once.
    func testTheSavingsBadgeIsComputedFromTheRealPrices() {
        XCTAssertEqual(
            PaywallView.savingsBadge(monthlyPrice: 2.99, yearlyPrice: 14.99),
            "SAVE 58%"
        )
        XCTAssertEqual(
            PaywallView.savingsBadge(monthlyPrice: 2.99, yearlyPrice: 29.99),
            "SAVE 16%"
        )
    }

    /// If a storefront prices the year above twelve months, the app must not
    /// claim a discount it is not offering.
    func testNoBadgeWhenTheYearlyPlanIsNotTheCheaperDeal() {
        XCTAssertNil(PaywallView.savingsBadge(monthlyPrice: 2.99, yearlyPrice: 40.00))
        XCTAssertNil(PaywallView.savingsBadge(monthlyPrice: 2.99, yearlyPrice: 35.88))
    }
}
