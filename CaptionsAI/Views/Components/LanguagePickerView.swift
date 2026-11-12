import SwiftUI

// MARK: - LanguagePickerView

/// Searchable list of every language a video can be transcribed in.
///
/// Picking a language that needs the Whisper model, before the model is on
/// the phone, first asks to download it: several hundred MB is not something
/// to start on someone's mobile data without saying so.
struct LanguagePickerView: View {
    @Binding var selection: TranscriptionLanguage
    let store: WhisperModelStore
    /// What to list. The editor's "Change" leaves out Auto-detect: it is
    /// there to say what the clip really is.
    var options: [TranscriptionLanguage] = TranscriptionLanguage.pickerOptions

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pendingDownload: TranscriptionLanguage?

    static let title = "Spoken Language"

    var body: some View {
        NavigationStack {
            List(TranscriptionLanguage.matching(query, in: options)) { language in
                Button {
                    choose(language)
                } label: {
                    row(for: language)
                }
                .accessibilityIdentifier("language-\(language.code)")
            }
            .listStyle(.plain)
            .overlay {
                if TranscriptionLanguage.matching(query, in: options).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        // iOS 26 draws this as an "X" labelled "Close", so
                        // the UI tests find it by identifier, not by label.
                        .accessibilityIdentifier("languagePickerCancel")
                }
            }
            .alert(
                Self.downloadTitle,
                isPresented: Binding(
                    get: { pendingDownload != nil },
                    set: { if !$0 { pendingDownload = nil } }
                ),
                presenting: pendingDownload
            ) { language in
                Button("Download") {
                    selection = language
                    store.startDownload()
                    pendingDownload = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    pendingDownload = nil
                }
            } message: { language in
                Text(Self.downloadMessage(for: language, megabytes: store.approximateMegabytes))
            }
        }
    }

    // MARK: - Choosing

    private func choose(_ language: TranscriptionLanguage) {
        if Self.needsDownloadConfirmation(for: language, modelDownloaded: store.downloadedFolder != nil, modelDownloading: store.isDownloading) {
            pendingDownload = language
        } else {
            selection = language
            dismiss()
        }
    }

    /// Whether picking `language` has to ask before it downloads anything.
    /// Not while the model is already downloading: the user agreed to it a
    /// moment ago, and being asked for "466 MB" again reads as a second
    /// download.
    static func needsDownloadConfirmation(
        for language: TranscriptionLanguage,
        modelDownloaded: Bool,
        modelDownloading: Bool = false
    ) -> Bool {
        language.engine == .whisper && !modelDownloaded && !modelDownloading
    }

    static let downloadTitle = "Download speech model?"

    static func downloadMessage(for language: TranscriptionLanguage, megabytes: Int) -> String {
        let subject = language.isAutoDetect
            ? "Auto-detect uses"
            : "Captions in \(language.name) use"
        return "\(subject) a \(megabytes) MB speech model that runs on your iPhone. "
            + "It downloads once and works for every language except English. Wi-Fi is recommended."
    }

    static let autoDetectSubtitle = "Works out the language from the first 30 seconds"

    // MARK: - Row

    private func row(for language: TranscriptionLanguage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.name)
                    .foregroundColor(.primary)
                if let native = language.isAutoDetect ? Self.autoDetectSubtitle : language.nativeName {
                    Text(native)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if language == selection {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppTheme.current.accentText)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - LanguageButton

/// The "Spoken language" row on the home screen: what new videos will be
/// transcribed in, and how the model download is going.
struct LanguageButton: View {
    let language: TranscriptionLanguage
    let modelState: WhisperModelStore.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(language.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                if let status = Self.status(for: language, modelState: modelState) {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("languageButton")
    }

    /// What the row says about the model, if anything. English needs no
    /// model, so it says nothing.
    static func status(for language: TranscriptionLanguage, modelState: WhisperModelStore.State) -> String? {
        guard language.engine == .whisper else { return nil }
        switch modelState {
        case let .downloading(fraction): return "Downloading \(Int(fraction * 100))%"
        case .failed: return "Download failed"
        case .notDownloaded: return "Model not downloaded"
        case .downloaded: return nil
        }
    }
}

// MARK: - DetectedLanguageChip

/// "Detected: Kannada · Change", over the top of the editor's video after
/// auto-detect has picked a language.
struct DetectedLanguageChip: View {
    let detection: LanguageDetection
    let onChange: () -> Void

    /// Below this, Whisper's pick is shown as a guess.
    static let unsureBelow = 0.5

    var body: some View {
        Button(action: onChange) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(Self.text(for: detection))
                Text("·")
                    .foregroundColor(.white.opacity(0.6))
                Text("Change")
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.current.accentText)
            }
            .font(.footnote)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
        }
        .accessibilityIdentifier("detectedLanguageChip")
    }

    static func text(for detection: LanguageDetection) -> String {
        let name = detection.language.name
        return detection.confidence < unsureBelow ? "Detected: \(name)?" : "Detected: \(name)"
    }
}

