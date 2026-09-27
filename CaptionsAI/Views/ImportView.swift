import PhotosUI
import SwiftData
import SwiftUI

// MARK: - ImportView

/// Home screen for importing videos and viewing recent projects.
struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath
    @State private var viewModel = ImportViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var pendingDeletion: Project?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Import area
                importSection

                // Recent projects, or an acknowledgement that there are none
                if Self.showsEmptyState(projectCount: viewModel.recentProjects.count) {
                    EmptyProjectsView()
                } else {
                    recentProjectsSection
                }
            }
            .padding(.top, 20)
        }
        .navigationTitle("CaptionsAI")
        .feedbackMenu()
        .background(Color(uiColor: .systemBackground))
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await viewModel.handleVideoSelection(newItem, context: modelContext)
                selectedItem = nil
            }
        }
        .onChange(of: viewModel.createdProject) { _, project in
            if let project {
                navigationPath.append(AppScreen.editor(project))
            }
        }
        .onAppear {
            viewModel.loadRecentProjects(context: modelContext)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: {
                if !$0 {
                    viewModel.error = nil
                }
            }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        // Same wording as All Projects. The context-menu delete used to fire
        // straight away, taking the project's video with it, with no undo.
        .alert(
            AllProjectsView.deleteTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { project in
            Button(AllProjectsView.deleteConfirmLabel, role: .destructive) {
                viewModel.deleteProject(project, context: modelContext)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { project in
            Text(AllProjectsView.deletePrompt(for: project.name))
        }
    }

    // MARK: - Empty State

    /// Whether the home screen should say "no projects" rather than draw the
    /// strip.
    ///
    /// Trivial, and a static function anyway: it is the one place the
    /// condition is written down, so an inverted `!` here is a test failure
    /// rather than a screen nobody can explain. The count is the *loaded*
    /// count, which is capped — but the cap is never zero, so a capped strip
    /// and an empty library can never be confused.
    static func showsEmptyState(projectCount: Int) -> Bool {
        projectCount == 0
    }

    /// Whether to offer a way past the strip.
    ///
    /// Offered only when it leads somewhere new: at exactly the cap the strip
    /// already is the whole library, and a "See All" that opens the same ten
    /// rows is worse than no link at all. Takes the *total*, which is why the
    /// view model counts separately from what it loads.
    static func showsSeeAll(totalProjectCount: Int) -> Bool {
        totalProjectCount > ImportViewModel.recentProjectsLimit
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(spacing: 24) {
            // Dashed border area
            VStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)

                Text("Import Video")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Pick a video from your library to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(.gray.opacity(0.3))
            )
            .padding(.horizontal, 24)

            // PhotosPicker button
            PhotosPicker(
                selection: $selectedItem,
                matching: .videos
            ) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(viewModel.isLoading ? "Importing..." : "Choose Video")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Recent Projects Section

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Projects")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                if Self.showsSeeAll(totalProjectCount: viewModel.totalProjectCount) {
                    NavigationLink(value: AppScreen.allProjects) {
                        Text("See All")
                            .font(.subheadline.weight(.semibold))
                            // #A78BFA rather than the #7C3AED used elsewhere:
                            // the darker purple is 3.69:1 on black and fails
                            // the 4.5:1 contrast minimum for body text.
                            .foregroundColor(Color(hex: "#A78BFA"))
                    }
                }
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.recentProjects) { project in
                        NavigationLink(value: AppScreen.editor(project)) {
                            ProjectCard(project: project)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Empty Projects View

/// Shown under the import box when the library is empty.
///
/// `ContentUnavailableView` deliberately without a symbol. Its usual shape is
/// a large glyph over a title, but this screen already opens with a 48pt
/// `film.stack` inside the import box; a second hero glyph a couple of hundred
/// points below it reads as a second, competing call to action and pushes the
/// real one — the Choose Video button — towards the fold on a small phone.
/// Passing only a title and a description keeps it to a quiet footnote, which
/// is all an empty list needs to be.
///
/// Internal rather than private so its copy and its height can be asserted;
/// the risk being guarded is that it grows.
struct EmptyProjectsView: View {
    static let title = "No projects yet"
    static let message = "Videos you caption will show up here."

    var body: some View {
        ContentUnavailableView {
            Text(Self.title)
        } description: {
            Text(Self.message)
        }
    }
}

// MARK: - Project Card

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Thumbnail
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
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Text(project.formattedDuration)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }

            Text(project.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
    }
}
