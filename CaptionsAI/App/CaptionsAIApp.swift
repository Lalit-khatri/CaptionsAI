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
                .tint(Color(hex: "#7C3AED"))
        }
        .modelContainer(for: [Project.self, CaptionSegment.self])
    }
}
