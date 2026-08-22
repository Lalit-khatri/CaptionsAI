import SwiftUI

// MARK: - ContentView

/// Root view that handles onboarding flow and main navigation.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreKitManager.self) private var storeKit
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        if appState.hasCompletedOnboarding {
            NavigationStack(path: $navigationPath) {
                ImportView(navigationPath: $navigationPath)
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .editor(let project):
                            EditorView(project: project)
                        case .preview(let project):
                            PreviewView(project: project)
                        case .export(let project):
                            ExportView(project: project)
                        case .paywall:
                            PaywallView()
                        default:
                            ImportView(navigationPath: $navigationPath)
                        }
                    }
            }
        } else {
            OnboardingView()
        }
    }
}
