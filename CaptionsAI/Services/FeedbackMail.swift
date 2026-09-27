import Foundation
import MessageUI

/// The two things the action button offers.
///
/// Hoisted out of the menu as data because a `Menu`'s content closure is not
/// reachable from a test — "the menu offers exactly these two actions" is only
/// assertable if the actions exist somewhere other than inside the menu.
enum FeedbackKind: String, CaseIterable, Identifiable {
    case feedback
    case featureRequest

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .feedback: return "Send feedback"
        case .featureRequest: return "Request a feature"
        }
    }

    var menuIcon: String {
        switch self {
        case .feedback: return "bubble.left.and.text.bubble.right"
        case .featureRequest: return "lightbulb"
        }
    }

    var subject: String {
        switch self {
        case .feedback: return "CaptionsAI feedback"
        case .featureRequest: return "CaptionsAI feature request"
        }
    }

    /// Sits at the top of the composed mail so the user knows what to write.
    var prompt: String {
        switch self {
        case .feedback: return "What's working, and what isn't?"
        case .featureRequest: return "What would you like CaptionsAI to do?"
        }
    }
}

/// Everything the feedback feature says and sends, as plain values.
///
/// The app has no backend and is not getting one: it is sold on the promise
/// that video never leaves the device, and an app that opens a socket to
/// deliver a bug report makes that promise inaccurate as App Store metadata,
/// not merely as a matter of taste. So feedback travels by mail, composed by
/// the user, sent by the user.
///
/// Nothing here reads `Bundle`, `UIDevice` or `Locale`. The diagnostics are
/// passed in. That is what lets a test state what the mail contains.
enum FeedbackMail {
    /// The one place the address appears.
    ///
    /// Worth knowing: once this is compiled into a shipped binary it cannot be
    /// changed without a release, and it will be scraped. An alias that
    /// forwards would be the safer thing to ship.
    static let address = "lk.khatri558@gmail.com"

    /// Every SF Symbol this feature draws, named here rather than at each use
    /// site so a test can check them. A symbol name that does not resolve
    /// renders as nothing at all — a toolbar button that is invisible but
    /// still tappable, which no compiler and no other test would catch.
    static let buttonSymbol = "ellipsis.circle"
    static let privacySymbol = "hand.raised"
    static let versionSymbol = "info.circle"

    static let privacyTitle = "Privacy Policy"

    /// The read-only "Version 1.0 (7)" row at the bottom of the menu.
    ///
    /// The build number is included because it is what distinguishes two
    /// TestFlight builds of the same marketing version when a user reports a
    /// bug.
    static func versionLabel(version: String, build: String) -> String {
        "Version \(version) (\(build))"
    }

    /// `mailto:` has no documented length limit and Apple Mail is generous,
    /// but third-party clients vary and a body that is silently cut in the
    /// middle is worse than one that says it was cut.
    static let messageLimit = 2000

    static let truncationMarker = "\n\n[message truncated]"

    // MARK: - Encoding

    /// The only characters that survive unencoded: RFC 3986's unreserved set.
    ///
    /// Deliberately an explicit allow-list rather than
    /// `.urlQueryAllowed.subtracting(…)`. `.urlQueryAllowed` leaves `&`, `+`,
    /// `=` and `?` alone because they are legal *query* characters — so a user
    /// who writes "captions & styles" loses everything after the ampersand,
    /// and one who writes "C++" may have the pluses read as spaces. Neither
    /// shows up in polite ASCII testing. `URLComponents` does not fix it
    /// either: it is RFC 3986-compliant and leaves `+` alone, which is the
    /// whole reason `percentEncodedQueryItems` exists.
    ///
    /// The allow-list also guarantees non-ASCII is percent-encoded rather than
    /// handed raw to `URL(string:)`, which would return nil and kill the
    /// feature for every user who does not write in English.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    // MARK: - What gets sent

    /// The four things that are safe to attach without asking.
    ///
    /// App version and build are our own bundle. The iOS version and the
    /// locale are coarse and shared by millions — and the locale is the single
    /// most useful field for a captions app, because it says which speech
    /// recogniser was in play.
    ///
    /// Not here, deliberately: the hardware model. Every design that reached
    /// for it planned to call `sysctlbyname("hw.machine")`, and the App Store
    /// privacy scanner reads *symbols*, not argument strings — `sysctlbyname`
    /// is the gateway symbol for the system-boot-time required-reason
    /// category. Also not here: anything derived from the user's media. No
    /// project name, no file name, no transcript, no caption text. That is the
    /// line that actually matters for this app.
    static func diagnostics(version: String, build: String, systemVersion: String, locale: String) -> String {
        "CaptionsAI \(version) (\(build)) · iOS \(systemVersion) · \(locale)"
    }

    /// The mail body, with the diagnostics visible inside it.
    ///
    /// Visible on purpose. Apple's optional-disclosure exception — the reason
    /// this app can keep saying "Data Not Collected" — requires that the user
    /// can see exactly what is being submitted and chooses to submit it each
    /// time. A composer the user reads and can edit satisfies that; a silent
    /// upload would not.
    static func body(kind: FeedbackKind, message: String, diagnostics: String) -> String {
        var text = message
        if text.count > messageLimit {
            text = String(text.prefix(messageLimit)) + truncationMarker
        }

        return """
        \(kind.prompt)

        \(text)


        ——
        \(diagnostics)
        Delete the line above if you would rather not send it.
        """
    }

    /// The `mailto:` URL, for when the in-app composer is not available.
    static func url(kind: FeedbackKind, body: String) -> URL? {
        URL(string: "mailto:\(address)?subject=\(encode(kind.subject))&body=\(encode(body))")
    }

    /// Appended wherever a mail route fails, so the address itself is always
    /// the way out.
    static let writeDirectlyHint = "You can write to \(address) directly."

    // MARK: - When Apple Mail has no account

    static let contactTitle = "Contact CaptionsAI"
    static let contactExplanation = "Mail isn't set up on this iPhone. Copy the address, or pick another app to send from."
    static let addressHeader = "Email"
    static let copyAddressTitle = "Copy address"
    static let copiedTitle = "Copied"
    static let shareTitle = "Send another way…"
    static let defaultMailTitle = "Open default mail app"

    static let copySymbol = "doc.on.doc"
    static let copiedSymbol = "checkmark"
    static let shareSymbol = "square.and.arrow.up"
    static let defaultMailSymbol = "envelope"

    /// What the share sheet carries. Most apps it reaches — Messages,
    /// WhatsApp, Notes — have no recipient field, so the address and subject
    /// travel inside the text rather than being lost.
    static func shareText(kind: FeedbackKind, body: String) -> String {
        """
        To: \(address)
        Subject: \(kind.subject)

        \(body)
        """
    }

    // MARK: - Telling the truth afterwards

    /// The composer hands back a result and every word of this matters.
    ///
    /// `.saved` means the user tapped Cancel then Save Draft: the mail is
    /// sitting in Drafts and will never arrive. An app that says "thanks for
    /// the feedback" there is lying. And `.sent` only means Mail accepted it
    /// — there is no delivery confirmation available to an app, ever, so the
    /// copy must not promise one.
    static func message(for result: MFMailComposeResult) -> String {
        switch result {
        case .sent:
            return "Thanks — handed to Mail to send."
        case .saved:
            return "Saved to your Mail drafts. It has not gone anywhere yet."
        case .failed:
            return "Mail could not send that. \(writeDirectlyHint)"
        case .cancelled:
            return ""
        @unknown default:
            return ""
        }
    }
}
