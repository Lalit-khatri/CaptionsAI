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

    @Query(sort: \Project.modifiedAt, order: .reverse)
    private var projects: [Project]

    var body: some View {
        List {
            ForEach(projects) { project in
                NavigationLink(value: AppScreen.editor(project)) {
                    ProjectRow(project: project)
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
