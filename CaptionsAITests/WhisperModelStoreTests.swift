@testable import CaptionsAI
import Foundation
import XCTest

// MARK: - Whisper fakes

/// A model download that never touches the network. It makes the folder a
/// real download would, and can be held part-way until the test lets it go.
final class FakeWhisperDownloader: WhisperModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private var _requestedVariants: [String] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false

    /// Hold every download at 50% until `release()`.
    let holds: Bool
    /// Thrown instead of finishing.
    var failure: Error?

    init(holds: Bool = false, failure: Error? = nil) {
        self.holds = holds
        self.failure = failure
    }

    var callCount: Int { lock.withLock { _callCount } }
    var requestedVariants: [String] { lock.withLock { _requestedVariants } }

    func release() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            released = true
            defer { waiting = [] }
            return waiting
        }
        pending.forEach { $0.resume() }
    }

    func download(
        variant: String,
        into base: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        lock.withLock {
            _callCount += 1
            _requestedVariants.append(variant)
        }
        progress(0.5)
        if holds {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if released { return true }
                    waiting.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        if let failure { throw failure }
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        progress(1)
        return folder
    }
}

struct FakeDownloadError: Error {}

/// A temporary model directory and defaults suite per test.
struct WhisperTestSandbox {
    let baseDirectory: URL
    let defaults: UserDefaults
    let suiteName: String

    init(name: String = UUID().uuidString) {
        suiteName = "WhisperTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    func makeStore(
        variant: String = WhisperModelChoice.preferred,
        downloader: any WhisperModelDownloading
    ) -> WhisperModelStore {
        WhisperModelStore(variant: variant, downloader: downloader, defaults: defaults, baseDirectory: baseDirectory)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}

// MARK: - Tests

@MainActor
final class WhisperModelStoreTests: XCTestCase {
    private var sandbox: WhisperTestSandbox!

    override func setUp() {
        super.setUp()
        sandbox = WhisperTestSandbox()
    }

    override func tearDown() {
        sandbox.tearDown()
        super.tearDown()
    }

    // MARK: - Choosing a model

    func testTheMultilingualSmallModelIsPreferredWhereThePhoneCanRunIt() {
        XCTAssertEqual(
            WhisperModelChoice.variant(supported: ["openai_whisper-base", "openai_whisper-small"]),
            "openai_whisper-small"
        )
    }

    func testOlderPhonesGetBase() {
        // WhisperKit's table for A12 and A13 stops at base.
        XCTAssertEqual(
            WhisperModelChoice.variant(supported: ["openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small.en"]),
            "openai_whisper-base"
        )
    }

    func testTheConfirmationQuotesTheRightSize() {
        XCTAssertEqual(WhisperModelChoice.approximateMegabytes(of: "openai_whisper-small"), 466)
        XCTAssertEqual(WhisperModelChoice.approximateMegabytes(of: "openai_whisper-base"), 142)
    }

    // MARK: - Downloading

    func testANewInstallHasNoModel() {
        let store = sandbox.makeStore(downloader: FakeWhisperDownloader())
        XCTAssertEqual(store.state, .notDownloaded)
        XCTAssertNil(store.downloadedFolder)
    }

    func testAskingForTheModelDownloadsItOnce() async throws {
        let downloader = FakeWhisperDownloader()
        let store = sandbox.makeStore(downloader: downloader)

        let folder = try await store.modelFolder()
        await waitUntil("download to be recorded") { store.state == .downloaded }

        XCTAssertEqual(folder.lastPathComponent, WhisperModelChoice.preferred)
        XCTAssertEqual(downloader.requestedVariants, [WhisperModelChoice.preferred])
        _ = try await store.modelFolder()
        XCTAssertEqual(downloader.callCount, 1, "a downloaded model was fetched again")
    }

    func testTheModelIsStillThereAfterARelaunch() async throws {
        let first = sandbox.makeStore(downloader: FakeWhisperDownloader())
        _ = try await first.modelFolder()
        await waitUntil("download to be recorded") { first.state == .downloaded }

        let downloader = FakeWhisperDownloader()
        let relaunched = sandbox.makeStore(downloader: downloader)
        XCTAssertEqual(relaunched.state, .downloaded)
        _ = try await relaunched.modelFolder()
        XCTAssertEqual(downloader.callCount, 0)
    }

    func testTheFolderIsRememberedRelativeToTheBase() async throws {
        // The app container moves on update; an absolute path would not.
        let store = sandbox.makeStore(downloader: FakeWhisperDownloader())
        _ = try await store.modelFolder()
        await waitUntil("download to be recorded") { store.state == .downloaded }
        XCTAssertEqual(
            sandbox.defaults.string(forKey: "whisperModelFolder.\(WhisperModelChoice.preferred)"),
            "models/argmaxinc/whisperkit-coreml/\(WhisperModelChoice.preferred)"
        )
    }

    func testAModelDeletedFromDiskCountsAsNotDownloaded() async throws {
        let store = sandbox.makeStore(downloader: FakeWhisperDownloader())
        let folder = try await store.modelFolder()
        await waitUntil("download to be recorded") { store.state == .downloaded }
        try FileManager.default.removeItem(at: folder)

        XCTAssertNil(sandbox.makeStore(downloader: FakeWhisperDownloader()).downloadedFolder)
    }

    func testTwoCallersShareOneDownload() async throws {
        let downloader = FakeWhisperDownloader(holds: true)
        let store = sandbox.makeStore(downloader: downloader)

        store.startDownload()
        let waiter = Task { try await store.modelFolder() }
        await waitUntil("download to start") { downloader.callCount == 1 }
        downloader.release()
        _ = try await waiter.value

        XCTAssertEqual(downloader.callCount, 1)
    }

    func testProgressIsReportedWhileDownloading() async {
        let downloader = FakeWhisperDownloader(holds: true)
        let store = sandbox.makeStore(downloader: downloader)

        store.startDownload()
        await waitUntil("progress to arrive") { store.state == .downloading(fraction: 0.5) }
        downloader.release()
        await waitUntil("download to finish") { store.state == .downloaded }
    }

    func testAFailedDownloadCanBeRetried() async {
        let failing = FakeWhisperDownloader(failure: FakeDownloadError())
        let store = sandbox.makeStore(downloader: failing)

        do {
            _ = try await store.modelFolder()
            XCTFail("download should have failed")
        } catch {
            XCTAssertTrue(error is FakeDownloadError)
        }
        await waitUntil("failure to be recorded") { store.state == .failed }

        failing.failure = nil
        _ = try? await store.modelFolder()
        await waitUntil("retry to finish") { store.state == .downloaded }
        XCTAssertEqual(failing.callCount, 2)
    }

    func testCancellingAWaiterLeavesTheDownloadRunning() async throws {
        let downloader = FakeWhisperDownloader(holds: true)
        let store = sandbox.makeStore(downloader: downloader)

        let waiter = Task { try await store.modelFolder() }
        await waitUntil("download to start") { downloader.callCount == 1 }
        waiter.cancel()

        let outcome = await waiter.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError) }

        downloader.release()
        await waitUntil("abandoned download to finish anyway") { store.state == .downloaded }
        XCTAssertEqual(downloader.callCount, 1)
    }
}
