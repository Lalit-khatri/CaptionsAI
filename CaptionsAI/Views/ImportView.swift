import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ImportView

/// Home screen for importing videos and viewing recent projects.
struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ImportViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var navigateToEditor = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Import area
                importSection
                
                // Recent projects
                if !viewModel.recentProjects.isEmpty {
                    recentProjectsSection
                }
            }
            .padding(.top, 20)
        }
        .navigationTitle("CaptionsAI")
        .background(Color(uiColor: .systemBackground))
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await viewModel.handleVideoSelection(newItem, context: modelContext)
                selectedItem = nil
            }
        }
        .navigationDestination(isPresented: $navigateToEditor) {
            if let project = viewModel.createdProject {
                EditorView(project: project)
            }
        }
        .onChange(of: viewModel.createdProject) { _, project in
            if project != nil {
                navigateToEditor = true
            }
        }
        .onAppear {
            viewModel.loadRecentProjects(context: modelContext)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
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
            Text("Recent Projects")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.recentProjects) { project in
                        NavigationLink(value: AppScreen.editor(project)) {
                            ProjectCard(project: project)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteProject(project, context: modelContext)
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

// MARK: - Project Card

private struct ProjectCard: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let data = project.thumbnailData,
                   let uiImage = UIImage(data: data) {
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
            .frame(width: 140, height: 100)
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
