import MessageUI
import SwiftUI
import UIKit

/// Apple Mail's composer, presented inside this app.
///
/// It does not dismiss itself — the delegate callback has to do it, which
/// here means clearing the state that presents the sheet.
struct MailComposer: UIViewControllerRepresentable {
    let kind: FeedbackKind
    let body: String
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.address])
        controller.setSubject(kind.subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_: MFMailComposeViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error _: Error?
        ) {
            onFinish(result)
        }
    }
}

/// The action button in the top-right of every screen worth giving feedback
/// from.
///
/// Two routes to the same inbox, in the order they are offered:
///
/// 1. The in-app composer, which is the one that keeps the user here. It is
///    also the one that satisfies Apple's optional-disclosure exception,
///    because the diagnostics are visible in a body the user can edit before
///    sending.
/// 2. A `mailto:` URL, for the user whose only mail app is Gmail —
///    `canSendMail()` reports only on Apple Mail, so that user would otherwise
///    be told, wrongly, that they cannot send mail.
///
/// When neither can be started, the banner spells out the address. Below the
/// mail actions sit the Privacy Policy link and the app version.
///
/// Two traps this deliberately avoids. `canOpenURL` is never called: without
/// an `LSApplicationQueriesSchemes` declaration it returns false even when a
/// handler exists, so asking first is what creates the bug. And there is
/// exactly one presentation modifier here, attached to the content rather
/// than to anything inside `ToolbarItem` — a sheet attached inside a `Menu`'s
/// content closure never presents at all.
struct FeedbackMenuModifier: ViewModifier {
    @Environment(\.openURL) private var openURL

    @State private var composing: FeedbackKind?
    @State private var banner: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(FeedbackKind.allCases) { kind in
                            Button {
                                start(kind)
                            } label: {
                                Label(kind.menuTitle, systemImage: kind.menuIcon)
                            }
                        }

                        // What App Review and a US privacy request both
                        // expect to find without hunting: the policy, and
                        // which build the user is on.
                        Section {
                            Button {
                                openURL(PaywallView.privacyPolicyURL)
                            } label: {
                                Label(FeedbackMail.privacyTitle, systemImage: FeedbackMail.privacySymbol)
                            }

                            // Read-only. A row in a menu that is not a
                            // button renders disabled, which is what a
                            // version is.
                            Label(versionLabel, systemImage: FeedbackMail.versionSymbol)
                        }
                    } label: {
                        Image(systemName: FeedbackMail.buttonSymbol)
                    }
                    // Not "More options", which tells a VoiceOver user
                    // nothing about what is behind the button.
                    .accessibilityLabel("Feedback and app info")
                }
            }
            .sheet(item: $composing) { kind in
                MailComposer(kind: kind, body: mailBody(for: kind)) { result in
                    composing = nil
                    show(FeedbackMail.message(for: result))
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                if let text = banner {
                    Text(text)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                        // A banner rather than an alert: two `.alert`
                        // modifiers in one hierarchy fight, and at least one
                        // of these screens already carries one for its own
                        // errors.
                        .allowsHitTesting(false)
                        .task(id: text) {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { banner = nil }
                        }
                }
            }
    }

    // MARK: - Routing

    private func start(_ kind: FeedbackKind) {
        if MFMailComposeViewController.canSendMail() {
            composing = kind
            return
        }

        guard let url = FeedbackMail.url(kind: kind, body: mailBody(for: kind)) else {
            show("Could not open a mail draft. \(FeedbackMail.writeDirectlyHint)")
            return
        }

        openURL(url) { accepted in
            if !accepted {
                show("No mail app is set up on this phone. \(FeedbackMail.writeDirectlyHint)")
            }
        }
    }

    private func show(_ message: String) {
        guard !message.isEmpty else { return }
        withAnimation { banner = message }
    }

    // MARK: - What goes in the mail

    private static let unknownValue = "unknown"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? Self.unknownValue
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? Self.unknownValue
    }

    private var versionLabel: String {
        FeedbackMail.versionLabel(version: appVersion, build: appBuild)
    }

    /// Read here, at the edge, and passed in as plain values — which is what
    /// lets the tests state what the mail contains.
    private var diagnostics: String {
        FeedbackMail.diagnostics(
            version: appVersion,
            build: appBuild,
            systemVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier
        )
    }

    /// The message is empty: the user types it. The prompt and the visible
    /// diagnostics are already in place around the gap.
    private func mailBody(for kind: FeedbackKind) -> String {
        FeedbackMail.body(kind: kind, message: "", diagnostics: diagnostics)
    }
}

extension View {
    /// Puts the feedback menu in this screen's top-right corner.
    func feedbackMenu() -> some View {
        modifier(FeedbackMenuModifier())
    }
}
