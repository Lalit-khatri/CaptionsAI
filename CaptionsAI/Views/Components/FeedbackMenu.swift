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
/// Two routes to the same inbox:
///
/// 1. The in-app composer, whenever Apple Mail has an account. It is also the
///    one that satisfies Apple's optional-disclosure exception, because the
///    diagnostics are visible in a body the user can edit before sending.
/// 2. Otherwise, `FeedbackContactSheet`: the address with a copy button, the
///    share sheet, and the default mail app as an explicit choice.
///
/// Route 2 used to be a `mailto:` opened straight away. When Apple Mail is
/// the default and has no account, `open` reports **success** and Mail shows
/// its own setup screen — there is no callback in which to offer anything
/// else. Asking the user first is the only way to avoid that dead end.
///
/// Below the mail actions sit the Privacy Policy link and the app version.
///
/// There is exactly one presentation modifier here, attached to the content
/// rather than to anything inside `ToolbarItem` — a sheet attached inside a
/// `Menu`'s content closure never presents at all.
struct FeedbackMenuModifier: ViewModifier {
    @Environment(\.openURL) private var openURL

    @State private var presented: FeedbackSheet?
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
            .sheet(item: $presented) { sheet in
                switch sheet {
                case .compose(let kind):
                    MailComposer(kind: kind, body: mailBody(for: kind)) { result in
                        presented = nil
                        show(FeedbackMail.message(for: result))
                    }
                    .ignoresSafeArea()
                case .contact(let kind):
                    FeedbackContactSheet(kind: kind, mailBody: mailBody(for: kind))
                }
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
        presented = MFMailComposeViewController.canSendMail() ? .compose(kind) : .contact(kind)
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

/// What the feedback menu's single `.sheet` is showing.
private enum FeedbackSheet: Identifiable {
    case compose(FeedbackKind)
    case contact(FeedbackKind)

    var id: String {
        switch self {
        case .compose(let kind): return "compose-\(kind.id)"
        case .contact(let kind): return "contact-\(kind.id)"
        }
    }
}

/// Shown instead of Apple's composer when Apple Mail has no account.
///
/// Every row is something the user picks, so none of them can silently land
/// on Mail's "set up an account" screen the way an automatic `mailto:` did.
struct FeedbackContactSheet: View {
    let kind: FeedbackKind
    let mailBody: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var copied = false
    @State private var failure: String?

    static let detents: Set<PresentationDetent> = [.medium, .large]
    static let copiedResetDelay: Duration = .seconds(2)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(FeedbackMail.address)
                        .textSelection(.enabled)

                    Button {
                        copyAddress()
                    } label: {
                        Label(
                            copied ? FeedbackMail.copiedTitle : FeedbackMail.copyAddressTitle,
                            systemImage: copied ? FeedbackMail.copiedSymbol : FeedbackMail.copySymbol
                        )
                    }
                } header: {
                    Text(FeedbackMail.addressHeader)
                } footer: {
                    Text(FeedbackMail.contactExplanation)
                }

                Section {
                    ShareLink(
                        item: FeedbackMail.shareText(kind: kind, body: mailBody),
                        subject: Text(kind.subject)
                    ) {
                        Label(FeedbackMail.shareTitle, systemImage: FeedbackMail.shareSymbol)
                    }

                    Button {
                        openDefaultMail()
                    } label: {
                        Label(FeedbackMail.defaultMailTitle, systemImage: FeedbackMail.defaultMailSymbol)
                    }
                } footer: {
                    if let failure {
                        Text(failure)
                    }
                }
            }
            .navigationTitle(FeedbackMail.contactTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: Self.copiedResetDelay)
                copied = false
            }
        }
        .presentationDetents(Self.detents)
    }

    private func copyAddress() {
        UIPasteboard.general.string = FeedbackMail.address
        copied = true
    }

    /// Still offered, but now as a named choice: for someone whose default
    /// mail app is not in any list we could make, it is the right answer.
    private func openDefaultMail() {
        guard let url = FeedbackMail.url(kind: kind, body: mailBody) else {
            failure = "Could not build a mail draft. \(FeedbackMail.writeDirectlyHint)"
            return
        }

        openURL(url) { accepted in
            if accepted {
                dismiss()
            } else {
                failure = "No mail app could open that. \(FeedbackMail.writeDirectlyHint)"
            }
        }
    }
}
