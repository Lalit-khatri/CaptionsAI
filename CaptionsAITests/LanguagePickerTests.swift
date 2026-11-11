@testable import CaptionsAI
import XCTest

final class LanguagePickerTests: XCTestCase {
    private let kannada = TranscriptionLanguage.with(code: "kn")!

    // MARK: - Asking before downloading

    func testPickingKannadaWithoutTheModelAsksFirst() {
        XCTAssertTrue(LanguagePickerView.needsDownloadConfirmation(for: kannada, modelDownloaded: false))
    }

    func testOnceTheModelIsThereNoOtherLanguageAsksAgain() {
        XCTAssertFalse(LanguagePickerView.needsDownloadConfirmation(for: kannada, modelDownloaded: true))
    }

    func testEnglishNeverAsks() {
        XCTAssertFalse(LanguagePickerView.needsDownloadConfirmation(for: .english, modelDownloaded: false))
    }

    func testTheConfirmationNamesTheLanguageTheSizeAndWiFi() {
        XCTAssertEqual(
            LanguagePickerView.downloadMessage(for: kannada, megabytes: 466),
            "Captions in Kannada use a 466 MB speech model that runs on your iPhone. "
                + "It downloads once and works for every language except English. Wi-Fi is recommended."
        )
    }

    func testAutoDetectAsksFirstToo() {
        XCTAssertTrue(LanguagePickerView.needsDownloadConfirmation(for: .autoDetect, modelDownloaded: false))
        XCTAssertFalse(LanguagePickerView.needsDownloadConfirmation(for: .autoDetect, modelDownloaded: true))
    }

    func testTheAutoDetectConfirmationReadsAsASentence() {
        XCTAssertEqual(
            LanguagePickerView.downloadMessage(for: .autoDetect, megabytes: 466),
            "Auto-detect uses a 466 MB speech model that runs on your iPhone. "
                + "It downloads once and works for every language except English. Wi-Fi is recommended."
        )
    }

    // MARK: - Home screen row

    func testEnglishShowsNoModelStatus() {
        XCTAssertNil(LanguageButton.status(for: .english, modelState: .notDownloaded))
        XCTAssertNil(LanguageButton.status(for: .english, modelState: .downloading(fraction: 0.5)))
    }

    func testTheRowShowsDownloadProgress() {
        XCTAssertEqual(LanguageButton.status(for: kannada, modelState: .downloading(fraction: 0.42)), "Downloading 42%")
    }

    func testTheRowSaysWhenTheDownloadFailedOrHasNotHappened() {
        XCTAssertEqual(LanguageButton.status(for: kannada, modelState: .failed), "Download failed")
        XCTAssertEqual(LanguageButton.status(for: kannada, modelState: .notDownloaded), "Model not downloaded")
    }

    func testADownloadedModelNeedsNoStatus() {
        XCTAssertNil(LanguageButton.status(for: kannada, modelState: .downloaded))
    }
}
