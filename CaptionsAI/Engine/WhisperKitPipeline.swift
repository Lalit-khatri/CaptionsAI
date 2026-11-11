import Foundation
import WhisperKit

// The only file that imports WhisperKit. Everything else talks to Whisper
// through `WhisperModelDownloading`, `WhisperPipelineLoading` and
// `WhisperPipeline`, so the rest of the app and its tests build and run
// without a model.
//
// `WordTiming` below is the app's own type: a module's declarations shadow
// imported ones, and WhisperKit's identically named struct is only ever
// reached through `segment.words`.

// MARK: - Download

struct WhisperKitDownloader: WhisperModelDownloading {
    /// The model to fetch on this device, from WhisperKit's table of what
    /// each chip can run.
    static func recommendedVariant() -> String {
        WhisperModelChoice.variant(supported: WhisperKit.recommendedModels().supported)
    }

    func download(
        variant: String,
        into base: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base) { update in
            progress(update.fractionCompleted)
        }
        // The model folder has no tokenizer; WhisperKit fetches it on first
        // load. Fetch it now, under the same base, so that the first
        // transcription after the download does not need the network too.
        _ = try await ModelUtilities.loadTokenizer(
            for: variant.contains("small") ? .small : .base,
            tokenizerFolder: base
        )
        return folder
    }
}

// MARK: - Load

struct WhisperKitLoader: WhisperPipelineLoading {
    /// Where `WhisperKitDownloader` left the tokenizer. Without it WhisperKit
    /// looks in, and downloads to, Documents.
    var tokenizerFolder: URL = WhisperModelStore.defaultBaseDirectory

    func load(modelFolder: URL) async throws -> any WhisperPipeline {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )
        return WhisperKitPipeline(kit: try await WhisperKit(config))
    }
}

// MARK: - Transcribe

final class WhisperKitPipeline: WhisperPipeline, @unchecked Sendable {
    private let kit: WhisperKit

    init(kit: WhisperKit) {
        self.kit = kit
    }

    func transcribe(
        audioPath: String,
        language: String,
        shouldContinue: @escaping @Sendable () -> Bool,
        onSegment: @escaping @Sendable (_ endSeconds: Double, _ text: String) -> Void
    ) async throws -> [WordTiming] {
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            // Prefill the language token rather than detect it: the user
            // said what the video is in, and detection on a short clip of
            // Kannada can land on Telugu or Tamil.
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            // Splits long audio at silences so clips past Whisper's 30 s
            // window are decoded whole rather than cut mid-word.
            chunkingStrategy: .vad
        )

        kit.segmentDiscoveryCallback = { segments in
            for segment in segments {
                onSegment(Double(segment.end), segment.text)
            }
        }
        defer { kit.segmentDiscoveryCallback = nil }

        let results = try await kit.transcribe(audioPath: audioPath, decodeOptions: options) { _ in
            shouldContinue()
        }
        return results
            .flatMap(\.segments)
            .flatMap { $0.words ?? [] }
            .map { WordTiming(word: $0.word, startTime: Double($0.start), endTime: Double($0.end)) }
    }

    func detectLanguage(audioPath: String) async throws -> (code: String, confidence: Double) {
        let result = try await kit.detectLanguage(audioPath: audioPath)
        // WhisperKit reports the log probability of the language it picked.
        let logProbability = result.langProbs[result.language] ?? -.infinity
        return (result.language, Double(exp(logProbability)))
    }
}
