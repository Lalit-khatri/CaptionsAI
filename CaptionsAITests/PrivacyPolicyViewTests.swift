@testable import CaptionsAI
import XCTest

final class PrivacyPolicyViewTests: XCTestCase {
    func testThePolicyShipsInsideTheApp() throws {
        let document = try XCTUnwrap(PolicyDocument.bundled(), "PRIVACY.md is not in the app bundle")
        XCTAssertEqual(document.blocks.first, .title("Privacy Policy — CaptionsAI"))
    }

    func testTheBundledPolicyCoversTheModelDownload() throws {
        let document = try XCTUnwrap(PolicyDocument.bundled())
        let text = document.blocks.map { block -> String in
            switch block {
            case let .title(t), let .heading(t), let .subheading(t), let .paragraph(t), let .bullet(t): return t
            }
        }.joined(separator: " ")
        XCTAssertTrue(text.contains("Hugging Face"), "the in-app policy is out of date")
    }

    func testHeadingsParagraphsAndBulletsAreSplit() {
        let document = PolicyDocument(markdown: """
        # Title

        ## Section
        First line
        second line.

        ### Part
        - **One** item
          that wraps
        - Two
        After.
        """)
        XCTAssertEqual(document.blocks, [
            .title("Title"),
            .heading("Section"),
            .paragraph("First line second line."),
            .subheading("Part"),
            .bullet("**One** item that wraps"),
            .bullet("Two"),
            .paragraph("After."),
        ])
    }

    func testInlineMarkdownBecomesStyledTextWithLinks() {
        let styled = PrivacyPolicyView.inline("See [Apple](https://www.apple.com/legal/privacy/) and **this**.")
        XCTAssertEqual(String(styled.characters), "See Apple and this.")
        XCTAssertTrue(styled.runs.contains { $0.link == URL(string: "https://www.apple.com/legal/privacy/") })
    }

    func testTheMenuOpensItInItsOwnSheet() {
        XCTAssertEqual(FeedbackSheet.privacyPolicy.id, "privacyPolicy")
    }
}
