import SwiftData
import SwiftUI

// MARK: - AllProjectsView

/// Every project, for when the home strip's ten are not the one you want.
///
/// Uses `@Query` rather than a fetch held on a view model. The home screen's
/// `ImportViewModel` holds `[Project]` it fetched once and reloads by hand on
/// `onAppear`; a list that can delete its own rows needs the store to tell it
/// when a row is gone, or it renders a `PersistentModel` that no longer backs
/// anything. `@Query` is that subscription, and it is the only `@Query` in the
/// app for that reason.
struct AllProjectsView: View {
    static let title = "All Projects"

    /// `.swipeActions` defaults to `allowsFullSwipe: true`, which fires the
    /// first destructive button when the row is dragged far enough — no tap on
    /// the button at all. This delete takes a video file with it and cannot be
    /// undone, so it has to be asked for deliberately.
    static let allowsFullSwipeDelete = false

    static let deleteTitle = "Delete Project"
    static let deleteConfirmLabel = "Delete"

    static func deletePrompt(for projectName: String) -> String {
        "\(projectName) and its video will be removed from this device. This can't be undone."
    }

    /// The full list's delete, as a function rather than a closure in the body,
    /// so the thing the swipe button runs is the thing the tests run.
    static func delete(_ project: Project, context: ModelContext) {
        ProjectDeletion.delete(project, context: context)
    }

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Project.modifiedAt, order: .reverse)
    private var projects: [Project]

    @State private var pendingDeletion: Project?

    var body: some View {
        List {
            ForEach(projects) { project in
                NavigationLink(value: AppScreen.editor(project)) {
                    ProjectRow(project: project)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: Self.allowsFullSwipeDelete) {
                    Button(role: .destructive) {
                        pendingDeletion = project
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if projects.isEmpty {
                EmptyProjectsView()
            }
        }
        // Attached to the List, not to the row. A row can be removed from the
        // hierarchy by the very delete the alert is confirming, and an alert
        // attached to a view that has gone never presents.
        .alert(
            Self.deleteTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { project in
            Button(Self.deleteConfirmLabel, role: .destructive) {
                Self.delete(project, context: modelContext)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { project in
            Text(Self.deletePrompt(for: project.name))
        }
    }
}

// MARK: - Project Row

/// A project as a list row: wide and short, where ``ProjectCard`` on the home
/// strip is narrow and tall.
private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let data = project.thumbnailData,
                   let uiImage = UIImage(data: data)
                {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                    Image(systemName: "film")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(project.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
