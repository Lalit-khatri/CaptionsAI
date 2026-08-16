import SwiftUI

// MARK: - ExportView

/// Export screen with format selection, quality toggle, and progress.
struct ExportView: View {
    let project: Project
    @Environment(StoreKitManager.self) private var storeKit
    @State private var viewModel = ExportViewModel()
    @State private var showPaywall = false
    @State private var showShareSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Format selection
                formatSection
                
                // Quality toggle
                qualitySection
                
                // Progress / Export button
                if viewModel.isExporting {
                    progressSection
                } else if let _ = viewModel.exportedFileURL {
                    completedSection
                } else {
                    exportButton
                }
            }
            .padding(.top, 16)
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(items: [url])
            }
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
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Format")
                .font(.headline)
                .padding(.horizontal, 24)
            
            VStack(spacing: 8) {
                ForEach(ExportPreset.allCases) { preset in
                    FormatCard(
                        preset: preset,
                        isSelected: viewModel.selectedPreset == preset
                    )
                    .onTapGesture {
                        viewModel.selectedPreset = preset
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Quality Section
    
    private var qualitySection: some View {
        HStack {
            Text("Quality")
                .font(.headline)
            
            Spacer()
            
            Picker("Quality", selection: $viewModel.quality) {
                ForEach(ExportQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: viewModel.exportEngine.progress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(viewModel.exportEngine.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    
                    Text("Exporting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .padding(.vertical, 24)
            
            Button("Cancel") {
                viewModel.cancelExport()
            }
            .foregroundColor(.red)
        }
    }
    
    // MARK: - Completed Section
    
    private var completedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Export Complete!")
                .font(.title3.bold())
            
            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.saveToPhotos() }
                } label: {
                    Label("Save to Photos", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#7C3AED"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
    }
    
    // MARK: - Export Button
    
    private var exportButton: some View {
        Button {
            if !viewModel.checkExportQuota(isPro: storeKit.isPro) {
                showPaywall = true
                AnalyticsService.paywallShown(trigger: "export_limit")
            } else {
                guard let videoURL = project.videoURL else { return }
                Task {
                    await viewModel.startExport(
                        videoURL: videoURL,
                        segments: project.sortedSegments,
                        style: project.selectedStyle,
                        isPro: storeKit.isPro
                    )
                }
            }
        } label: {
            Label("Export Video", systemImage: "square.and.arrow.up")
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
        .padding(.horizontal, 24)
    }
}

// MARK: - Format Card

private struct FormatCard: View {
    let preset: ExportPreset
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.iconName)
                .font(.title2)
                .foregroundColor(isSelected ? Color(hex: "#7C3AED") : .gray)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.displayName)
                    .font(.body.bold())
                    .foregroundColor(.white)
                
                Text("\(preset.aspectRatioString), \(preset.resolutionString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "#7C3AED"))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(hex: "#7C3AED") : .clear, lineWidth: 2)
        )
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
