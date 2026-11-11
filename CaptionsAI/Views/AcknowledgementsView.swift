import SwiftUI

// MARK: - Acknowledgement

/// Third-party software the app ships, with the notices its licence requires
/// the app to carry.
///
/// WhisperKit is MIT-licensed, which asks for its copyright and permission
/// notice to be included with every copy; parts of it come from Hugging
/// Face's swift-transformers, under Apache 2.0, whose licence text and
/// attribution travel in WhisperKit's NOTICES file. Both are bundled verbatim
/// from the WhisperKit release `project.yml` pins, rather than retyped.
struct Acknowledgement: Identifiable, Equatable {
    let name: String
    let licenseName: String
    let url: URL
    /// Text files in the app bundle, shown one after another.
    let resources: [String]

    var id: String { name }

    static let whisperKit = Acknowledgement(
        name: "WhisperKit",
        licenseName: "MIT License; includes code from swift-transformers (Apache License 2.0)",
        url: URL(string: "https://github.com/argmaxinc/WhisperKit")!,
        resources: ["WhisperKit-LICENSE", "WhisperKit-NOTICES"]
    )

    static let all: [Acknowledgement] = [whisperKit]

    /// The bundled notices, or nil if any file is missing from `bundle`.
    /// Nil rather than a partial text: a licence notice with a piece missing
    /// is not the notice the licence asks for.
    func text(in bundle: Bundle = .main) -> String? {
        var parts: [String] = []
        for resource in resources {
            guard let url = bundle.url(forResource: resource, withExtension: "txt"),
                  let contents = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            parts.append(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - AcknowledgementsView

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    static let title = "Acknowledgements"

    var body: some View {
        NavigationStack {
            List(Acknowledgement.all) { item in
                NavigationLink {
                    AcknowledgementDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.licenseName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("acknowledgementsDone")
                }
            }
        }
    }
}

private struct AcknowledgementDetailView: View {
    let item: Acknowledgement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(item.url.absoluteString, destination: item.url)
                    .font(.footnote)
                Text(item.text() ?? "The licence text is missing from this build.")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
