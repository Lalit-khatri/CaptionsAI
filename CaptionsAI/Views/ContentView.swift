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
                        // Exhaustive on purpose. A `default:` here turns a
                        // destination somebody forgot to wire into a second
                        // copy of the home screen, pushed on top of the first,
                        // which is indistinguishable from a navigation bug.
                        switch screen {
                        case let .editor(project):
                            EditorView(project: project)
                        case let .preview(project):
                            PreviewView(project: project)
                        case let .export(project):
                            ExportView(project: project)
                        case .paywall:
                            PaywallView()
                        case .allProjects:
                            AllProjectsView()
                        case .onboarding, .importVideo:
                            ImportView(navigationPath: $navigationPath)
                        }
                    }
            }
        } else {
            OnboardingView()
        }
    }
}
