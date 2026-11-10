import Foundation

// MARK: - Transcribing

/// The slice of `SpeechRecognizer` that the editor actually depends on.
///
/// This exists so the editor's transcription lifecycle can be tested without
/// the Speech framework. That lifecycle is where the app's worst defect lives —
/// a cancelled run whose late completion deletes the user's edited captions
/// from the store — and it is untestable against a real `SFSpeechRecognizer`,
/// which needs authorization, audio and a network round trip.
///
/// The two observable properties are here because `EditorView` renders them in
/// the processing overlay. Reading them through the protocol still goes via
/// `@Observable`'s generated accessors, so SwiftUI observation is unaffected.
protocol Transcribing: AnyObject {
    var progress: Double { get }
    var partialResults: [String] { get }

    /// Instance-level bridge to `SFSpeechRecognizer.requestAuthorization`.
    ///
    /// It has to be on the seam rather than called statically: in a unit-test
    /// host there is nobody to answer the permission prompt, so the real call
    /// resolves to denied and every transcription test would stop at the
    /// authorization guard without reaching the code under test.
    func requestAuthorization() async -> Bool

    /// What the recogniser is getting ready, while it does; nil otherwise.
    var preparation: TranscriptionPreparation? { get }

    /// One-off work that has to happen before the first recognition, such as
    /// downloading a speech model.
    ///
    /// Separate from `recognizeSpeech` because the editor bounds recognition
    /// by a deadline scaled to the clip's length. A model download depends on
    /// the network, not the clip, and a 466 MB download cut off at ninety
    /// seconds would fail every time on a slow connection.
    func prepare() async throws

    func recognizeSpeech(from videoURL: URL) async throws -> [CaptionSegment]
}

/// The stages a recogniser can be in before it starts listening.
enum TranscriptionPreparation: Equatable {
    /// Downloading the speech model; `fraction` is 0...1.
    case downloading(fraction: Double)
    /// Loading the downloaded model into memory. Not measurable.
    case loading
}

extension Transcribing {
    var preparation: TranscriptionPreparation? { nil }
    func prepare() async throws {}
}

extension SpeechRecognizer: Transcribing {
    func requestAuthorization() async -> Bool {
        await SpeechRecognizer.requestAuthorization()
    }
}
