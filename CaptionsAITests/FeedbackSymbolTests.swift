@testable import CaptionsAI
import UIKit
import XCTest

/// Every SF Symbol the feedback menu draws has to exist.
///
/// A name that does not resolve is not a crash and not a compile error. The
/// image is simply nil and the control renders as empty space — in this case
/// an invisible but still tappable button in the corner of four screens. The
/// only way to find that is to ask UIKit, which is what this does.
///
/// Same shape as the guard that every typeface named by a caption preset
/// resolves: the interesting failures in this app are the silent ones.
final class FeedbackSymbolTests: XCTestCase {
    private func assertResolves(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(
            UIImage(systemName: name),
            "SF Symbol \"\(name)\" does not resolve — it will draw as nothing",
            file: file, line: line
        )
    }

    func testTheButtonItselfHasAnIcon() {
        assertResolves(FeedbackMail.buttonSymbol)
    }

    func testTheCopyActionHasAnIcon() {
        assertResolves(FeedbackMail.copySymbol)
    }

    func testEveryMenuActionHasAnIcon() {
        for kind in FeedbackKind.allCases {
            assertResolves(kind.menuIcon)
        }
    }

    /// The control: a name that cannot exist must fail, or the four tests
    /// above are asserting nothing.
    func testAnInventedSymbolNameDoesNotResolve() {
        XCTAssertNil(UIImage(systemName: "captionsai.not.a.real.symbol"))
    }
}
