import Foundation

// MARK: - Model Choice

/// Which Whisper model this phone downloads.
///
/// The multilingual `small` model where WhisperKit says the phone can run it,
/// `base` where it cannot (A12 and A13 phones). The English-only `.en`
/// variants are no use here: English never reaches Whisper.
enum WhisperModelChoice {
    static let preferred = "openai_whisper-small"
    static let fallback = "openai_whisper-base"

    static func variant(supported: [String]) -> String {
        supported.contains(preferred) ? preferred : fallback
    }

    /// Download size in MB, as shown in the confirmation before downloading.
    static func approximateMegabytes(of variant: String) -> Int {
        variant == preferred ? 466 : 142
    }
}

// MARK: - Seams

/// Fetches a Whisper model's files. The real one goes to Hugging Face via
/// WhisperKit; tests supply one that does not touch the network.
protocol WhisperModelDownloading: Sendable {
    /// Downloads `variant` under `base` and returns the folder holding it.
    /// `progress` receives the completed fraction, 0...1, from any thread.
    func download(
        variant: String,
        into base: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

// MARK: - WhisperModelStore

/// Owns the one Whisper model on the phone: whether it is there, and the
/// download that puts it there.
///
/// Shared across the app so the language picker can start the download as
/// soon as a language is chosen, and an editor opened a minute later joins the
/// same download instead of starting a second one.
///
/// Not `@MainActor` as a whole, because `state` is read from the synchronous
/// `Transcribing.preparation`; everything that changes it is.
@Observable
final class WhisperModelStore {
    enum State: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case downloaded
        /// The last download failed; asking again starts a new one.
        case failed
    }

    static let shared = WhisperModelStore(
        variant: WhisperKitDownloader.recommendedVariant(),
        downloader: WhisperKitDownloader(),
        baseDirectory: UITestLaunch(arguments: ProcessInfo.processInfo.arguments).usesInMemoryStore
            ? uiTestBaseDirectory
            : defaultBaseDirectory
    )

    /// An empty folder per UI-test launch, so a model downloaded by hand on
    /// the same simulator cannot change what the tests see.
    private static var uiTestBaseDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestWhisperModels-\(UUID().uuidString)", isDirectory: true)
    }

    let variant: String
    private(set) var state: State = .notDownloaded

    private let downloader: any WhisperModelDownloading
    private let defaults: UserDefaults
    private let baseDirectory: URL
    private var download: Task<URL, Error>?

    init(
        variant: String,
        downloader: any WhisperModelDownloading,
        defaults: UserDefaults = .standard,
        baseDirectory: URL = WhisperModelStore.defaultBaseDirectory
    ) {
        self.variant = variant
        self.downloader = downloader
        self.defaults = defaults
        self.baseDirectory = baseDirectory
        state = downloadedFolder == nil ? .notDownloaded : .downloaded
    }

    /// Application Support rather than WhisperKit's default of Documents:
    /// Documents shows up in the Files app, and a model the user can browse
    /// to and delete by accident is a model that silently has to be fetched
    /// again.
    static var defaultBaseDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    var approximateMegabytes: Int {
        WhisperModelChoice.approximateMegabytes(of: variant)
    }

    // MARK: - Location

    private var folderKey: String { "whisperModelFolder.\(variant)" }

    /// The model's folder, if a download finished and its files are still
    /// there.
    ///
    /// Stored relative to the base directory. The app container's absolute
    /// path changes when the app is updated, so a stored absolute path would
    /// point nowhere after the first update and the model would be fetched
    /// again for nothing.
    var downloadedFolder: URL? {
        guard let relative = defaults.string(forKey: folderKey) else { return nil }
        let folder = baseDirectory.appendingPathComponent(relative, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// `folder`'s path below the base directory, or nil if it is not below it.
    func relativePath(of folder: URL) -> String? {
        let base = baseDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    // MARK: - Download

    /// Starts the download unless it is running or done. For the picker, so
    /// the model is on its way while the user is still choosing a video.
    @MainActor
    func startDownload() {
        guard downloadedFolder == nil else { return }
        _ = beginDownloadIfNeeded()
    }

    /// The model's folder, downloading it first if need be.
    ///
    /// Joins a download already running. Cancelling the caller stops it
    /// waiting but leaves the download going: leaving the editor should not
    /// throw away 400 MB that is nearly there.
    @MainActor
    func modelFolder() async throws -> URL {
        if let folder = downloadedFolder { return folder }
        return try await waitAbandoningOnCancel(beginDownloadIfNeeded())
    }

    @MainActor
    private func beginDownloadIfNeeded() -> Task<URL, Error> {
        if let download { return download }
        state = .downloading(fraction: 0)
        let task = Task { [downloader, variant, baseDirectory] in
            try Self.prepareBaseDirectory(baseDirectory)
            return try await downloader.download(variant: variant, into: baseDirectory) { fraction in
                Task { @MainActor [weak self] in self?.reportProgress(fraction) }
            }
        }
        download = task
        Task { await finish(task) }
        return task
    }

    @MainActor
    private func reportProgress(_ fraction: Double) {
        // Progress hops through the main queue after the fact; one arriving
        // after the download finished must not put the bar back up.
        guard download != nil, case .downloading = state else { return }
        state = .downloading(fraction: min(max(fraction, 0), 1))
    }

    @MainActor
    private func finish(_ task: Task<URL, Error>) async {
        let result = await task.result
        guard download == task else { return }
        download = nil
        switch result {
        case let .success(folder):
            if let relative = relativePath(of: folder) {
                defaults.set(relative, forKey: folderKey)
            }
            state = .downloaded
        case .failure:
            state = .failed
        }
    }

    /// Creates the folder and keeps it out of iCloud backups: the model is
    /// several hundred MB of public data that can always be fetched again.
    private static func prepareBaseDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = directory
        try excluded.setResourceValues(values)
    }
}

// MARK: - Abandonable Wait

/// Waits for `task`, but gives up with `CancellationError` as soon as the
/// caller is cancelled, without cancelling `task` itself.
///
/// `await task.value` does neither: it ignores the caller's cancellation and
/// waits until the task ends however long that takes.
func waitAbandoningOnCancel<T>(_ task: Task<T, Error>) async throws -> T {
    let gate = CancellationGate()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let once = OneShotClaim()
            Task {
                let result = await task.result
                if once.claim() { continuation.resume(with: result) }
            }
            gate.attach {
                if once.claim() { continuation.resume(throwing: CancellationError()) }
            }
        }
    } onCancel: {
        gate.cancel()
    }
}
