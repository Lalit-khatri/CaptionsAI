import SwiftData
import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// MARK: - CaptionsAI App Entry Point

@main
struct CaptionsAIApp: App {
    @State private var appState = AppState()
    @State private var storeKitManager = StoreKitManager()
    /// Set only when the UI tests launch the app; see `UITestLaunch`.
    @State private var testContainer: ModelContainer? = {
        do {
            return try UITestLaunch.current.makeTestContainer()
        } catch {
            fatalError("UI test store could not be created: \(error)")
        }
    }()

    init() {
        #if canImport(FirebaseCore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            #if canImport(FirebaseAnalytics)
            AnalyticsService.shared.provider = FirebaseAnalyticsProvider()
            #endif
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(storeKitManager)
                .preferredColorScheme(.dark)
                .themedTint()
                .uiTestContainer(testContainer)
        }
        .modelContainer(for: [Project.self, CaptionSegment.self])
    }
}

private extension View {
    /// Swaps in the UI tests' in-memory store. The inner `.modelContainer`
    /// wins over the scene's, so the on-disk library is never read or
    /// written during a UI test, and without one nothing changes.
    @ViewBuilder
    func uiTestContainer(_ container: ModelContainer?) -> some View {
        if let container {
            modelContainer(container)
        } else {
            self
        }
    }
}
