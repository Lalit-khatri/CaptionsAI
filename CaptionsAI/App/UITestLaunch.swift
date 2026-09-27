import Foundation
import SwiftData

// MARK: - UITestLaunch

/// What the UI tests ask of the app at launch, read from its arguments.
///
/// Every UI test starts from a known library without touching the real one:
/// an in-memory store, optionally seeded. With none of these arguments, which
/// is every launch outside the UI tests, nothing here has any effect.
///
/// Onboarding is not handled here. `AppState` reads `hasCompletedOnboarding`
/// from `UserDefaults.standard`, and a `-hasCompletedOnboarding YES|NO` launch
/// argument lands in the arguments domain, which takes precedence over the
/// stored value for the life of the process and is never written back.
struct UITestLaunch: Equatable {
    /// Use an empty in-memory store instead of the on-disk library.
    static let inMemoryStoreArgument = "-uiTestInMemoryStore"
    /// Followed by a `Seed` raw value. Implies an in-memory store.
    static let seedArgument = "-uiTestSeed"

    /// A library a UI test can start from.
    enum Seed: String, CaseIterable {
        /// One project with two captions and no video file, so the editor
        /// opens without transcribing.
        case projectWithCaptions
        /// One project with no captions and no video file.
        case emptyProject
    }

    /// The seeded project's name, which the tests look for on the home screen.
    static let seededProjectName = "UI Test Project"
    /// The seeded captions, in order.
    static let seededCaptions = ["Hello from the UI tests", "A second caption"]
    /// A path that is never a file, so the seeded project's video is missing.
    static let seededVideoPath = "/uitest/missing-video.mov"

    var usesInMemoryStore = false
    var seed: Seed?

    /// No UI-test behaviour at all.
    static let none = UITestLaunch()

    /// Reads the launch arguments. An unknown seed is ignored rather than
    /// guessed at, but still asks for an in-memory store: a test that meant to
    /// seed must never run against the real library.
    init(arguments: [String]) {
        usesInMemoryStore = arguments.contains(Self.inMemoryStoreArgument)
        if let index = arguments.firstIndex(of: Self.seedArgument) {
            usesInMemoryStore = true
            let valueIndex = arguments.index(after: index)
            if valueIndex < arguments.endIndex {
                seed = Seed(rawValue: arguments[valueIndex])
            }
        }
    }

    init(usesInMemoryStore: Bool = false, seed: Seed? = nil) {
        self.usesInMemoryStore = usesInMemoryStore
        self.seed = seed
    }

    /// The launch this process was started with.
    static let current = UITestLaunch(arguments: ProcessInfo.processInfo.arguments)

    // MARK: - Store

    /// An in-memory container, seeded as asked, when a UI test wants one;
    /// otherwise nil, and the app keeps its on-disk library untouched.
    ///
    /// Not main-actor bound, so it can run from a stored property's initial
    /// value: the seed goes through its own context and is saved, which the
    /// in-memory store then serves to the main context like any other data.
    func makeTestContainer() throws -> ModelContainer? {
        guard usesInMemoryStore else { return nil }
        let schema = Schema([Project.self, CaptionSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        if let seed {
            let context = ModelContext(container)
            Self.insert(seed, into: context)
            try context.save()
        }
        return container
    }

    /// Adds the seeded library to `context`.
    static func insert(_ seed: Seed, into context: ModelContext) {
        let project = Project(
            name: seededProjectName,
            videoURL: URL(fileURLWithPath: seededVideoPath),
            videoDuration: 10
        )
        context.insert(project)

        guard seed == .projectWithCaptions else { return }
        for (index, text) in seededCaptions.enumerated() {
            let start = Double(index * 2)
            project.addSegment(CaptionSegment(startTime: start, endTime: start + 2, text: text, sortOrder: index))
        }
    }
}
