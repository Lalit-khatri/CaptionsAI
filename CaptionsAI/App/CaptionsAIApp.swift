import SwiftUI
import SwiftData

// MARK: - CaptionsAI App Entry Point

@main
struct CaptionsAIApp: App {
    @State private var appState = AppState()
    @State private var storeKitManager = StoreKitManager()
    
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
