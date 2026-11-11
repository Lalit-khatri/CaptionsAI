@testable import CaptionsAI
import XCTest

/// The open-source notices the app is required to carry are actually in the
/// build, word for word.
final class AcknowledgementsTests: XCTestCase {
    func testWhisperKitIsAcknowledged() {
        XCTAssertEqual(Acknowledgement.all.map(\.name), ["WhisperKit"])
    }

    func testWhisperKitsMITNoticeIsBundled() throws {
        let text = try XCTUnwrap(Acknowledgement.whisperKit.text(), "a licence file is missing from the app bundle")
        XCTAssertTrue(text.hasPrefix("MIT License"))
        XCTAssertTrue(text.contains("Copyright (c) 2024 argmax, inc."))
        XCTAssertTrue(text.contains("The above copyright notice and this permission notice shall be included in all"))
    }

    func testTheSwiftTransformersApacheNoticeIsBundled() throws {
        let text = try XCTUnwrap(Acknowledgement.whisperKit.text())
        XCTAssertTrue(text.contains("Copyright 2022 Hugging Face SAS."))
        XCTAssertTrue(text.contains("Apache License"))
        XCTAssertTrue(text.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
    }

    func testAMissingFileGivesNoTextRatherThanPartOfIt() {
        let broken = Acknowledgement(
            name: "Broken",
            licenseName: "MIT",
            url: URL(string: "https://example.com")!,
            resources: ["WhisperKit-LICENSE", "does-not-exist"]
        )
        XCTAssertNil(broken.text())
    }

    func testTheMenuOpensItInItsOwnSheet() {
        XCTAssertEqual(FeedbackSheet.acknowledgements.id, "acknowledgements")
    }
}
