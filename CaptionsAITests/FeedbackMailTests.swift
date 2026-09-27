@testable import CaptionsAI
import MessageUI
import XCTest

/// What the feedback feature actually sends, and what it says afterwards.
///
/// None of the UI is reachable from here — nothing in this bundle can observe
/// a toolbar, a menu, or a hand-off to Mail. What *is* reachable is every
/// string that leaves the app, which is where the failures that matter live:
/// a body silently cut at an ampersand, a "thanks for your feedback" shown
/// over a mail still sitting in Drafts.
final class FeedbackMailTests: XCTestCase {
    private let diagnostics = FeedbackMail.diagnostics(
        version: "1.0.0", build: "1", systemVersion: "18.1", locale: "en_GB"
    )

    private func url(_ message: String, kind: FeedbackKind = .feedback) throws -> String {
        let body = FeedbackMail.body(kind: kind, message: message, diagnostics: diagnostics)
        return try XCTUnwrap(FeedbackMail.url(kind: kind, body: body), "the mailto URL would not parse").absoluteString
    }

    // MARK: - The encoding, which is where this feature usually breaks

    /// The classic `mailto:` defect: an ampersand in the body reads as the
    /// start of a new parameter, and everything the user wrote after it is
    /// dropped. Silently, and never in English test data.
    func testAnAmpersandInTheMessageSurvives() throws {
        let string = try url("the styles & fonts screen")

        XCTAssertTrue(string.contains("%26"), "the ampersand was not encoded")
        XCTAssertEqual(
            string.filter { $0 == "&" }.count, 1,
            "a raw ampersand in the body will truncate the mail at that point"
        )
    }

    /// The reason this code does not use `.urlQueryAllowed`, stated as a test
    /// rather than as a comment. If this ever starts failing, the convenient
    /// approach has become correct and the hand-rolled set can go.
    func testTheConvenientEncodingWouldStillGetThisWrong() {
        let naive = "the styles & fonts screen, C++"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        XCTAssertTrue(naive?.contains("&") ?? false, ".urlQueryAllowed no longer leaves & raw")
        XCTAssertTrue(naive?.contains("+") ?? false, ".urlQueryAllowed no longer leaves + raw")
    }

    func testAPlusSignSurvives() throws {
        let string = try url("crashes when I write C++")

        XCTAssertTrue(string.contains("C%2B%2B"), "a raw + is decoded as a space by some mail clients")
    }

    func testNewlinesSurvive() throws {
        let string = try url("first line\nsecond line")

        XCTAssertTrue(string.contains("%0A"))
    }

    /// A body that is not all-ASCII hands `URL(string:)` bytes it will refuse,
    /// which would return nil and kill the feature for everyone who does not
    /// write in English.
    func testANonEnglishMessageStillProducesAUrl() throws {
        let string = try url("les sous-titres ne s'affichent pas — 日本語でも")

        XCTAssertTrue(string.allSatisfy(\.isASCII), "the URL contains raw non-ASCII")
    }

    func testTheMessageGoesToTheOneAddressWeHave() throws {
        let string = try url("hello")

        XCTAssertTrue(string.hasPrefix("mailto:\(FeedbackMail.address)?"))
    }

    func testAVeryLongMessageIsCutVisibly() throws {
        let long = String(repeating: "a", count: FeedbackMail.messageLimit + 500)
        let body = FeedbackMail.body(kind: .feedback, message: long, diagnostics: diagnostics)

        XCTAssertTrue(body.contains("truncated"), "a body cut without saying so is worse than a long one")
        XCTAssertLessThan(body.count, FeedbackMail.messageLimit + 400)
    }

    // MARK: - What the user is shown before they send

    /// Apple's optional-disclosure exception is the reason this app can keep
    /// saying "Data Not Collected". It requires the user to see what is being
    /// submitted. So the diagnostics must be in the body, not attached
    /// invisibly to it.
    func testTheDiagnosticsAreVisibleInTheMailTheUserReads() {
        let body = FeedbackMail.body(kind: .feedback, message: "hello", diagnostics: diagnostics)

        XCTAssertTrue(body.contains(diagnostics))
        XCTAssertTrue(body.lowercased().contains("delete"), "the user is not told they can remove it")
    }

    func testTheDiagnosticsSayFourThingsAndNoMore() {
        XCTAssertTrue(diagnostics.contains("1.0.0"))
        XCTAssertTrue(diagnostics.contains("(1)"))
        XCTAssertTrue(diagnostics.contains("18.1"))
        XCTAssertTrue(diagnostics.contains("en_GB"))
    }

    /// The hardware model is absent on purpose: reading it means calling
    /// `sysctlbyname`, and the App Store privacy scanner matches symbols, not
    /// the argument you pass them.
    func testTheDiagnosticsDoNotIdentifyTheDevice() {
        let text = diagnostics.lowercased()

        XCTAssertFalse(text.contains("iphone1"), "a hardware model identifier is in the diagnostics")
        XCTAssertFalse(text.contains("-"), "a UUID-shaped identifier is in the diagnostics")
    }

    /// Nothing derived from the user's video may ever ride along.
    func testTheBodyCarriesNothingButWhatTheUserTyped() {
        let body = FeedbackMail.body(kind: .feedback, message: "captions are late", diagnostics: diagnostics)

        XCTAssertFalse(body.contains(".mov"))
        XCTAssertFalse(body.lowercased().contains("transcript"))
        XCTAssertFalse(body.lowercased().contains("project"))
    }

    // MARK: - The menu

    func testTheMenuOffersExactlyTwoActions() {
        XCTAssertEqual(FeedbackKind.allCases.count, 2)
        XCTAssertEqual(FeedbackKind.allCases.map(\.menuTitle), ["Send feedback", "Request a feature"])
    }

    func testTheTwoActionsArriveWithDifferentSubjects() {
        XCTAssertNotEqual(FeedbackKind.feedback.subject, FeedbackKind.featureRequest.subject)
        for kind in FeedbackKind.allCases {
            XCTAssertTrue(kind.subject.contains("CaptionsAI"), "\(kind) does not say which app it is about")
        }
    }

    func testTheVersionRowShowsVersionAndBuild() {
        XCTAssertEqual(FeedbackMail.versionLabel(version: "1.2.0", build: "37"), "Version 1.2.0 (37)")
    }

    // MARK: - When Apple Mail has no account

    /// Messages, WhatsApp and Notes have no recipient field, so the share
    /// text is the only place the address can travel.
    func testSharedTextCarriesTheAddressSubjectAndMessage() {
        let body = FeedbackMail.body(kind: .featureRequest, message: "batch export", diagnostics: diagnostics)
        let text = FeedbackMail.shareText(kind: .featureRequest, body: body)

        XCTAssertTrue(text.contains("To: lk.khatri558@gmail.com"))
        XCTAssertTrue(text.contains("Subject: CaptionsAI feature request"))
        XCTAssertTrue(text.contains("batch export"))
    }

    func testEachMailAppGetsAPrefilledDraftItCanParse() throws {
        let body = FeedbackMail.body(kind: .feedback, message: "styles & fonts", diagnostics: diagnostics)

        for app in MailApp.allCases {
            let url = try XCTUnwrap(app.composeURL(kind: .feedback, body: body), "\(app) URL would not parse")
            let string = url.absoluteString

            XCTAssertEqual(url.scheme, app.scheme)
            XCTAssertTrue(string.contains("lk.khatri558%40gmail.com"), "\(app) draft has no recipient")
            XCTAssertTrue(string.contains("styles%20%26%20fonts"), "\(app) draft would be cut at the ampersand")
        }
    }

    /// The exact drafts, written out, so a change to any parameter name or
    /// path — the part these undocumented schemes are fussy about — fails
    /// here rather than on a user's phone.
    func testGmailDraftURLIsExactlyTheDocumentedShape() {
        XCTAssertEqual(
            MailApp.gmail.composeURL(kind: .feedback, body: "hi")?.absoluteString,
            "googlegmail:///co?to=lk.khatri558%40gmail.com&subject=CaptionsAI%20feedback&body=hi"
        )
    }

    func testOutlookDraftURLIsExactlyTheDocumentedShape() {
        XCTAssertEqual(
            MailApp.outlook.composeURL(kind: .feedback, body: "hi")?.absoluteString,
            "ms-outlook://compose?to=lk.khatri558%40gmail.com&subject=CaptionsAI%20feedback&body=hi"
        )
    }

    /// Spark names the recipient `recipient`, not `to`.
    func testSparkDraftURLIsExactlyTheDocumentedShape() {
        XCTAssertEqual(
            MailApp.spark.composeURL(kind: .featureRequest, body: "hi")?.absoluteString,
            "readdle-spark://compose?recipient=lk.khatri558%40gmail.com&subject=CaptionsAI%20feature%20request&body=hi"
        )
    }

    /// Three parameters means exactly two raw ampersands. A third would be the
    /// user's own `&`, splitting their message into a bogus parameter.
    func testNoMailAppDraftHasAStrayAmpersand() throws {
        let body = FeedbackMail.body(kind: .feedback, message: "a & b && c", diagnostics: diagnostics)

        for app in MailApp.allCases {
            let string = try XCTUnwrap(app.composeURL(kind: .feedback, body: body)).absoluteString
            XCTAssertEqual(string.filter { $0 == "&" }.count, 2, "\(app) draft splits the message")
        }
    }

    /// Non-ASCII handed raw to `URL(string:)` returns nil, which would make the
    /// row do nothing for anyone not writing in English. Newlines and `+`
    /// must survive too: the body is multi-line and `+` can be read as space.
    func testMailAppDraftsSurviveNonASCIINewlinesAndPlus() throws {
        let body = "héllo 日本\nC++"

        for app in MailApp.allCases {
            let string = try XCTUnwrap(app.composeURL(kind: .feedback, body: body), "\(app) URL is nil").absoluteString
            XCTAssertTrue(string.hasSuffix("body=h%C3%A9llo%20%E6%97%A5%E6%9C%AC%0AC%2B%2B"), "\(app): \(string)")
        }
    }

    func testEveryMailAppHasADistinctSchemeAndAProbeURL() throws {
        XCTAssertEqual(Set(MailApp.allCases.map(\.scheme)).count, MailApp.allCases.count)

        for app in MailApp.allCases {
            let probe = try XCTUnwrap(app.probeURL, "\(app) probe URL would not parse")
            XCTAssertEqual(probe.absoluteString, "\(app.scheme)://")
        }
    }

    func testTheRowTitleNamesTheApp() {
        XCTAssertEqual(MailApp.allCases.map(\.menuTitle), ["Open in Gmail", "Open in Outlook", "Open in Spark"])
    }

    // MARK: - Which mail apps are offered

    func testNoMailAppIsOfferedWhenNoneIsInstalled() {
        XCTAssertEqual(MailApp.installed { _ in false }, [])
    }

    func testEveryMailAppIsOfferedWhenAllAreInstalled() {
        XCTAssertEqual(MailApp.installed { _ in true }, [.gmail, .outlook, .spark])
    }

    func testOnlyTheInstalledAppsAreOfferedInAStableOrder() {
        let installed: Set<String> = ["readdle-spark", "googlegmail"]

        let offered = MailApp.installed { url in installed.contains(url.scheme ?? "") }

        XCTAssertEqual(offered, [.gmail, .spark])
    }

    /// The probe asks about the scheme alone, not a compose URL: `canOpenURL`
    /// is only allowed for declared schemes, and a draft is not what is being
    /// asked about.
    func testInstallationIsProbedWithTheBareScheme() {
        var asked: [String] = []

        _ = MailApp.installed { url in
            asked.append(url.absoluteString)
            return false
        }

        XCTAssertEqual(asked, ["googlegmail://", "ms-outlook://", "readdle-spark://"])
    }

    // MARK: - Which sheet the menu opens

    func testAppleMailWithAnAccountGetsTheInAppComposer() {
        for kind in FeedbackKind.allCases {
            XCTAssertEqual(FeedbackSheet.route(for: kind, canSendMail: true), .compose(kind))
        }
    }

    /// The defect this replaced: with no account, a `mailto:` was opened
    /// without asking and could land on Mail's setup screen.
    func testAppleMailWithoutAnAccountGetsTheContactSheet() {
        for kind in FeedbackKind.allCases {
            XCTAssertEqual(FeedbackSheet.route(for: kind, canSendMail: false), .contact(kind))
        }
    }

    /// `.sheet(item:)` keys on `id`. If the composer and the contact sheet for
    /// the same kind shared one, switching between them would not re-present.
    func testEverySheetHasADistinctIdentity() {
        let sheets = FeedbackKind.allCases.flatMap { [FeedbackSheet.compose($0), .contact($0)] }
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }

    // MARK: - The share text and fallback copy

    func testSharedTextUsesEachKindsOwnSubject() {
        for kind in FeedbackKind.allCases {
            XCTAssertTrue(FeedbackMail.shareText(kind: kind, body: "x").contains("Subject: \(kind.subject)"))
        }
    }

    /// The body is passed through untouched, diagnostics and all — the user
    /// has already been shown them.
    func testSharedTextEndsWithTheBodyVerbatim() {
        let body = FeedbackMail.body(kind: .feedback, message: "hi", diagnostics: diagnostics)

        XCTAssertTrue(FeedbackMail.shareText(kind: .feedback, body: body).hasSuffix(body))
    }

    func testTheWriteDirectlyHintSpellsOutTheAddress() {
        XCTAssertEqual(FeedbackMail.writeDirectlyHint, "You can write to lk.khatri558@gmail.com directly.")
    }

    // MARK: - Telling the truth afterwards

    /// The one piece of copy in this feature that can lie. `.saved` means the
    /// mail is in Drafts and will never arrive.
    func testASavedDraftIsNotDescribedAsSent() {
        let text = FeedbackMail.message(for: .saved)

        XCTAssertTrue(text.lowercased().contains("draft"))
        XCTAssertFalse(text.lowercased().contains("sent"), "a draft is being described as sent")
        XCTAssertFalse(text.lowercased().contains("thank"), "the user is being thanked for a mail that never left")
    }

    func testCancellingSaysNothing() {
        XCTAssertTrue(FeedbackMail.message(for: .cancelled).isEmpty, "cancelling is not an event worth a banner")
    }

    func testAFailureOffersTheWayOut() {
        let text = FeedbackMail.message(for: .failed)

        XCTAssertTrue(text.contains("lk.khatri558@gmail.com"), "a failed send must say where to write instead")
    }

    /// `.sent` means Mail accepted it, not that it arrived. No app can know
    /// that it arrived, so the copy must not claim it.
    func testSendingDoesNotPromiseDelivery() {
        let text = FeedbackMail.message(for: .sent).lowercased()

        XCTAssertFalse(text.contains("delivered"))
        XCTAssertFalse(text.contains("received"))
    }
}
