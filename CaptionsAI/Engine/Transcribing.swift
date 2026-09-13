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

    func recognizeSpeech(from videoURL: URL) async throws -> [CaptionSegment]
}

extension SpeechRecognizer: Transcribing {
    func requestAuthorization() async -> Bool {
        await SpeechRecognizer.requestAuthorization()
    }
}
