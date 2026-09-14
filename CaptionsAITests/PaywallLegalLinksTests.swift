import XCTest

@testable import CaptionsAI

/// Guideline 3.1.2 requires a paid subscription to offer functional links to
/// both a Terms of Use (EULA) and a Privacy Policy, reachable from inside the
/// binary, on the screen that takes the money.
///
/// The paywall shipped a single grey `Text("Terms & Privacy")` — not a link,
/// not two documents, and tapping it did nothing. It sat directly beneath a
/// real `Button` for Restore Purchases, which is what made it read as
/// finished. This is among the most routinely cited 3.1.2 rejections there is,
/// and the reviewer's finding is unarguable because they will tap it.
///
/// What these tests can and cannot do: they pin that two distinct HTTPS
/// documents are configured and wired into the footer. They cannot fetch
/// either one, so a URL that returns 404 passes here. The Privacy Policy
/// therefore points at a file committed to this repository rather than at
/// hosting that has to be set up separately — the link works the moment the
/// commit lands, which is the property worth having.
final class PaywallLegalLinksTests: XCTestCase {

    func testBothRequiredDocumentsAreConfiguredOverHTTPS() {
        XCTAssertEqual(
            PaywallView.termsOfUseURL.scheme, "https",
            "App Review will not accept an http or custom-scheme legal link."
        )
        XCTAssertEqual(PaywallView.privacyPolicyURL.scheme, "https")
    }

    /// One link cannot satisfy both requirements, which is what the old single
    /// "Terms & Privacy" label implied.
    func testTermsAndPrivacyAreTwoSeparateDocuments() {
        XCTAssertNotEqual(
            PaywallView.termsOfUseURL, PaywallView.privacyPolicyURL,
            "Terms and Privacy must be two reachable documents, not one label."
        )
    }

    /// Apple's standard EULA is the default Terms of Use for any app that does
    /// not supply its own, and using it is explicitly allowed.
    func testTermsPointAtApplesStandardEULA() {
        XCTAssertEqual(
            PaywallView.termsOfUseURL.absoluteString,
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
    }

    /// The policy is a file in this repository. That is deliberate: it needs no
    /// hosting, no DNS and no separate deploy, so the link cannot rot
    /// independently of the code that points at it.
    func testThePrivacyPolicyIsAConcreteDocumentAndNotAPlaceholder() {
        let address = PaywallView.privacyPolicyURL.absoluteString
        XCTAssertTrue(
            address.contains("Lalit-khatri/CaptionsAI"),
            "The policy should live with the source, not on unowned hosting."
        )
        for placeholder in ["example.com", "TODO", "localhost", "yourdomain"] {
            XCTAssertFalse(
                address.lowercased().contains(placeholder.lowercased()),
                "The privacy policy URL is still a placeholder: \(address)"
            )
        }
    }

    /// Both documents must be reachable from the paywall itself. A constant
    /// nothing renders is the same defect as the inert label it replaced —
    /// this is the wiring check that stops the seams passing on their own.
    func testTheFooterOffersBothDocuments() {
        let titles = PaywallView.legalLinks.map(\.title)
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("terms") })
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("privacy") })

        let destinations = Set(PaywallView.legalLinks.map(\.url))
        XCTAssertEqual(
            destinations, [PaywallView.termsOfUseURL, PaywallView.privacyPolicyURL],
            "The footer must point at the two configured documents."
        )
    }
}
