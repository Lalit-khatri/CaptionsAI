import SwiftUI

// MARK: - PolicyDocument

/// PRIVACY.md, bundled with the app and split into blocks a SwiftUI view
/// can draw.
///
/// The same file the website serves, so the copy in the app can never say
/// something different from the one App Review reads online. Only the
/// Markdown the policy actually uses is understood: `#`/`##`/`###`
/// headings, `- ` bullets (with indented continuation lines), paragraphs,
/// and inline emphasis and links.
struct PolicyDocument: Equatable {
    enum Block: Equatable {
        case title(String)
        case heading(String)
        case subheading(String)
        case paragraph(String)
        case bullet(String)
    }

    static let resourceName = "PRIVACY"

    let blocks: [Block]

    /// The bundled policy, or nil if the file is missing from `bundle`.
    static func bundled(in bundle: Bundle = .main) -> PolicyDocument? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return PolicyDocument(markdown: text)
    }

    init(markdown: String) {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullet: [String]?

        func flush() {
            if let lines = bullet {
                blocks.append(.bullet(lines.joined(separator: " ")))
                bullet = nil
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("### ") {
                flush(); blocks.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush(); blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush(); blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flush(); bullet = [String(line.dropFirst(2))]
            } else if bullet != nil, rawLine.hasPrefix(" ") {
                bullet?.append(line)
            } else {
                if bullet != nil { flush() }
                paragraph.append(line)
            }
        }
        flush()
        self.blocks = blocks
    }
}

// MARK: - PrivacyPolicyView

/// The privacy policy, readable without a connection, with a link to the
/// published copy.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    static let title = "Privacy Policy"
    static let viewOnlineTitle = "View online"

    private let document = PolicyDocument.bundled()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let document {
                        ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                            view(for: block)
                        }
                    } else {
                        Text("The policy could not be loaded. It is also online at the link below.")
                            .foregroundColor(.secondary)
                    }
                    Link(Self.viewOnlineTitle, destination: PaywallView.privacyPolicyURL)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppTheme.current.accentText)
                        .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("privacyPolicyDone")
                }
            }
        }
    }

    @ViewBuilder
    private func view(for block: PolicyDocument.Block) -> some View {
        switch block {
        case let .title(text):
            Text(Self.inline(text)).font(.title2.bold())
        case let .heading(text):
            Text(Self.inline(text)).font(.headline).padding(.top, 8)
        case let .subheading(text):
            Text(Self.inline(text)).font(.subheadline.weight(.semibold)).padding(.top, 4)
        case let .paragraph(text):
            Text(Self.inline(text)).font(.subheadline)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(Self.inline(text))
            }
            .font(.subheadline)
        }
    }

    /// Bold, italics and links within a line. Falls back to the raw text if
    /// the Markdown does not parse, rather than showing nothing.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
