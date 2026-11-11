import Foundation

// MARK: - TranscriptionEngine

/// Which recogniser turns a clip's speech into captions.
enum TranscriptionEngine: Equatable {
    /// Apple's Speech framework. Built in, nothing to download, but on-device
    /// it has no Kannada and its Hindi is the dictation model.
    case apple
    /// Whisper, run on-device through WhisperKit. Needs a one-off model
    /// download, and covers every language Whisper was trained on.
    case whisper
}

// MARK: - TranscriptionLanguage

/// A language the user can say their video is spoken in.
///
/// Routed by language rather than by iOS version: English stays on Apple's
/// recogniser, which needs no download, and everything else goes to Whisper on
/// every supported iOS. Apple's newer `SpeechTranscriber` (iOS 26) still has no
/// Hindi or Kannada, so splitting on the OS version would have left the users
/// asking for those languages exactly where they are today.
struct TranscriptionLanguage: Hashable, Identifiable, Sendable {
    /// Whisper's language code, which is what its decoder is prompted with.
    /// Mostly ISO 639-1, with Whisper's own exceptions (`jw` for Javanese).
    let code: String

    /// English name, as Whisper's tokenizer spells it, title-cased. Used for
    /// the list and for search, so it reads the same whatever the phone's
    /// language is.
    let name: String

    var id: String { code }

    var engine: TranscriptionEngine {
        code == Self.english.code ? .apple : .whisper
    }

    /// Not a language: "let Whisper work out which language it is".
    var isAutoDetect: Bool { code == Self.autoDetect.code }

    /// The language's name for itself — "ಕನ್ನಡ", "हिन्दी" — when the system
    /// knows it, and nil when that would only repeat `name`.
    var nativeName: String? {
        guard !isAutoDetect else { return nil }
        let native = Locale(identifier: code).localizedString(forLanguageCode: code)
        guard let native, native.compare(name, options: .caseInsensitive) != .orderedSame else { return nil }
        return native
    }

    static let english = TranscriptionLanguage(code: "en", name: "English")

    /// Whisper listens to the first 30 seconds and picks the language.
    /// Needs the Whisper model, like any language other than English; a
    /// clip it decides is English is then transcribed by Whisper too, since
    /// the model is already loaded by then.
    static let autoDetect = TranscriptionLanguage(code: "auto", name: "Auto-detect")

    /// What the picker lists: Auto-detect, then every language.
    static let pickerOptions: [TranscriptionLanguage] = [autoDetect] + all

    /// Every language the multilingual Whisper `small` and `base` models know,
    /// English first and the rest alphabetically.
    ///
    /// Copied from WhisperKit's `Constants.languages` with its aliases
    /// (Castilian, Flemish, Mandarin, …) folded into one entry per code, and
    /// without Cantonese, whose token only exists in large-v3.
    static let all: [TranscriptionLanguage] = {
        let others = whisperLanguages
            .filter { $0.code != english.code }
            .map { TranscriptionLanguage(code: $0.code, name: $0.name) }
            .sorted { $0.name < $1.name }
        return [english] + others
    }()

    /// The picker option with `code`: a language Whisper knows, or
    /// Auto-detect.
    static func with(code: String) -> TranscriptionLanguage? {
        pickerOptions.first { $0.code == code }
    }

    /// `languages` whose English name, native name or code starts a word with
    /// `query`. An empty query matches everything.
    static func matching(_ query: String, in languages: [TranscriptionLanguage] = pickerOptions) -> [TranscriptionLanguage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return languages }
        return languages.filter { language in
            [language.name, language.nativeName ?? "", language.code].contains { candidate in
                candidate
                    .components(separatedBy: CharacterSet(charactersIn: " ()-"))
                    .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
            }
        }
    }

    private static let whisperLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("zh", "Chinese"), ("de", "German"), ("es", "Spanish"),
        ("ru", "Russian"), ("ko", "Korean"), ("fr", "French"), ("ja", "Japanese"),
        ("pt", "Portuguese"), ("tr", "Turkish"), ("pl", "Polish"), ("ca", "Catalan"),
        ("nl", "Dutch"), ("ar", "Arabic"), ("sv", "Swedish"), ("it", "Italian"),
        ("id", "Indonesian"), ("hi", "Hindi"), ("fi", "Finnish"), ("vi", "Vietnamese"),
        ("he", "Hebrew"), ("uk", "Ukrainian"), ("el", "Greek"), ("ms", "Malay"),
        ("cs", "Czech"), ("ro", "Romanian"), ("da", "Danish"), ("hu", "Hungarian"),
        ("ta", "Tamil"), ("no", "Norwegian"), ("th", "Thai"), ("ur", "Urdu"),
        ("hr", "Croatian"), ("bg", "Bulgarian"), ("lt", "Lithuanian"), ("la", "Latin"),
        ("mi", "Maori"), ("ml", "Malayalam"), ("cy", "Welsh"), ("sk", "Slovak"),
        ("te", "Telugu"), ("fa", "Persian"), ("lv", "Latvian"), ("bn", "Bengali"),
        ("sr", "Serbian"), ("az", "Azerbaijani"), ("sl", "Slovenian"), ("kn", "Kannada"),
        ("et", "Estonian"), ("mk", "Macedonian"), ("br", "Breton"), ("eu", "Basque"),
        ("is", "Icelandic"), ("hy", "Armenian"), ("ne", "Nepali"), ("mn", "Mongolian"),
        ("bs", "Bosnian"), ("kk", "Kazakh"), ("sq", "Albanian"), ("sw", "Swahili"),
        ("gl", "Galician"), ("mr", "Marathi"), ("pa", "Punjabi"), ("si", "Sinhala"),
        ("km", "Khmer"), ("sn", "Shona"), ("yo", "Yoruba"), ("so", "Somali"),
        ("af", "Afrikaans"), ("oc", "Occitan"), ("ka", "Georgian"), ("be", "Belarusian"),
        ("tg", "Tajik"), ("sd", "Sindhi"), ("gu", "Gujarati"), ("am", "Amharic"),
        ("yi", "Yiddish"), ("lo", "Lao"), ("uz", "Uzbek"), ("fo", "Faroese"),
        ("ht", "Haitian Creole"), ("ps", "Pashto"), ("tk", "Turkmen"), ("nn", "Nynorsk"),
        ("mt", "Maltese"), ("sa", "Sanskrit"), ("lb", "Luxembourgish"), ("my", "Myanmar (Burmese)"),
        ("bo", "Tibetan"), ("tl", "Tagalog"), ("mg", "Malagasy"), ("as", "Assamese"),
        ("tt", "Tatar"), ("haw", "Hawaiian"), ("ln", "Lingala"), ("ha", "Hausa"),
        ("ba", "Bashkir"), ("jw", "Javanese"), ("su", "Sundanese"),
    ]
}

// MARK: - LanguagePreference

/// The language new transcriptions are run in, remembered across launches.
///
/// One app-wide choice rather than one per project: someone captioning their
/// own Kannada videos picks it once, not on every import.
struct LanguagePreference {
    static let key = "transcriptionLanguage"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// English until the user picks something else. A stored code this build
    /// does not know also reads as English rather than as a language whose
    /// model cannot be asked for.
    var language: TranscriptionLanguage {
        get {
            defaults.string(forKey: Self.key).flatMap(TranscriptionLanguage.with(code:)) ?? .english
        }
        nonmutating set {
            defaults.set(newValue.code, forKey: Self.key)
        }
    }
}
