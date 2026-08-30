import SwiftUI
import AVFoundation

// MARK: - ExportView Constants

/// Horizontal padding for all sections
private let kSectionPadding: CGFloat = 24
/// Corner radius for cards and buttons
private let kCardCornerRadius: CGFloat = 12
/// Progress circle size
private let kProgressCircleSize: CGFloat = 120
/// Progress circle stroke width
private let kProgressStrokeWidth: CGFloat = 8

// MARK: - ExportView

/// Export screen with format/quality/codec selection, live progress, and auto-save.
struct ExportView: View {
    let project: Project
    @Environment(StoreKitManager.self) private var storeKit
    @State private var viewModel = ExportViewModel()
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var showCancelAlert = false
    @State private var videoDuration: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isExporting {
                exportingView
            } else if viewModel.exportedFileURL != nil {
                completedView
            } else {
                settingsView
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isExporting)
        .toolbar {
            if viewModel.isExporting {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Stop") {
                        showCancelAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .alert("Cancel Export?", isPresented: $showCancelAlert) {
            Button("Keep Exporting", role: .cancel) {}
            Button("Stop Export", role: .destructive) {
                viewModel.cancelExport()
            }
        } message: {
            Text("Your export progress will be lost.")
        }
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
        .onAppear {
            loadVideoDuration()
        }
    }

    // MARK: - State 1: Settings

    private var settingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Format preset
                formatSection

                // Resolution
                resolutionSection

                // Quality
                qualitySection

                // Codec
//                codecSection

                // Include Audio
                audioToggle

                // Export summary with file size
                exportSummary

                // Export button
                exportButton
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Format", icon: "film")

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
            .padding(.horizontal, kSectionPadding)
        }
    }

    // MARK: - Resolution Section

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Resolution", icon: "arrow.up.backward.and.arrow.down.forward")

            Picker("Resolution", selection: $viewModel.settings.resolution) {
                ForEach(ExportResolution.allCases) { res in
                    Text(res.displayName).tag(res)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, kSectionPadding)
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Quality", icon: "star")

            Picker("Quality", selection: $viewModel.settings.quality) {
                ForEach(ExportQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, kSectionPadding)
        }
    }

    // MARK: - Codec Section

    private var codecSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Codec", icon: "cpu")

            Picker("Codec", selection: $viewModel.settings.codec) {
                ForEach(ExportCodec.allCases) { codec in
                    Text(codec.rawValue).tag(codec)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, kSectionPadding)
        }
    }

    // MARK: - Audio Toggle

    private var audioToggle: some View {
        HStack {
            Label("Include Audio", systemImage: "speaker.wave.2")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: $viewModel.settings.includeAudio)
                .labelsHidden()
        }
        .padding(.horizontal, kSectionPadding)
    }

    // MARK: - Export Summary

    private var exportSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Summary", icon: "doc.text")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(resolutionLabel) • \(viewModel.settings.codec.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(.white)

                    Text("\(viewModel.settings.quality.rawValue) Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(viewModel.estimatedFileSize(videoDuration: videoDuration))
                    .font(.title3.bold())
                    .foregroundColor(Color(hex: "#7C3AED"))
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: kCardCornerRadius))
            .padding(.horizontal, kSectionPadding)
        }
    }

    private var resolutionLabel: String {
        let preset = viewModel.selectedPreset
        if preset == .original {
            return viewModel.settings.resolution.displayName
        }
        return "\(Int(preset.resolution.width))×\(Int(preset.resolution.height))"
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
                        captionYPosition: project.captionYPosition ?? project.selectedStyle.position.yPosition,
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
        .padding(.horizontal, kSectionPadding)
    }

    // MARK: - State 2: Exporting

    private var exportingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: kProgressStrokeWidth)

                Circle()
                    .trim(from: 0, to: viewModel.exportEngine.progress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: kProgressStrokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: viewModel.exportEngine.progress)

                VStack(spacing: 4) {
                    Text("\(Int(viewModel.exportEngine.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(.white)

                    Text("Exporting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: kProgressCircleSize, height: kProgressCircleSize)

            Spacer()

            Button("Cancel Export") {
                showCancelAlert = true
            }
            .foregroundColor(.red)
            .padding(.bottom, 40)
        }
    }

    // MARK: - State 3: Complete

    private var completedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Export Complete!")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("Saved to Photo Library")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                showShareSheet = true
            } label: {
                Label("Share Video", systemImage: "square.and.arrow.up")
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
            .padding(.horizontal, kSectionPadding)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, kSectionPadding)
    }

    private func loadVideoDuration() {
        guard let url = project.videoURL else { return }
        let asset = AVURLAsset(url: url)
        Task {
            let duration = try? await asset.load(.duration)
            if let d = duration {
                videoDuration = CMTimeGetSeconds(d)
            }
        }
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
        .clipShape(RoundedRectangle(cornerRadius: kCardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: kCardCornerRadius)
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
