import AVFoundation
import SwiftUI

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

/// Export screen with format/resolution selection, live progress, and auto-save.
struct ExportView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreKitManager.self) private var storeKit
    @State private var viewModel = ExportViewModel()
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var showCancelAlert = false
    @State private var videoDuration: Double = 0
    @State private var thumbnailImage: UIImage?
    @State private var didChooseInitialPreset = false

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
        .feedbackMenu()
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
            PaywallView(trigger: .exportLimit)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(items: [url])
            }
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
        .onAppear {
            loadVideoInfo()
            if !didChooseInitialPreset {
                didChooseInitialPreset = true
                let thumbnailSize = project.thumbnailData.flatMap(UIImage.init(data:))?.size
                viewModel.selectedPreset = ExportViewModel.initialPreset(
                    lastUsed: project.lastExportPreset,
                    sourceSize: thumbnailSize
                )
            }
        }
        // Remembered only once an export has worked: a format picked and
        // then abandoned says nothing about what the user wants next time.
        .onChange(of: viewModel.exportedFileURL) { _, url in
            if url != nil {
                project.lastExportPreset = viewModel.selectedPreset.rawValue
            }
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

                // Codec
//                codecSection

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
                // Short labels: in four segments "1080p Full HD" was cut to
                // "1080p Full...".
                ForEach(ExportResolution.allCases) { res in
                    Text(res.shortName).tag(res)
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
                    .foregroundColor(AppTheme.current.accent)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: kCardCornerRadius))
            .padding(.horizontal, kSectionPadding)
        }
    }

    private var resolutionLabel: String {
        ExportViewModel.resolutionLabel(preset: viewModel.selectedPreset, settings: viewModel.settings)
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            Task {
                // Pro status must be known before deciding on the paywall
                // and the watermark; see waitForInitialEntitlements.
                await storeKit.waitForInitialEntitlements()
                // The only path that raises the paywall. While this was
                // commented out the screen was unreachable, along with
                // everything on it.
                if !viewModel.checkExportQuota(isPro: storeKit.isPro) {
                    // PaywallView logs paywall_shown when it appears; logging
                    // here as well counted every limit hit twice.
                    showPaywall = true
                } else {
                    guard let videoURL = project.videoURL else { return }
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
                .foregroundColor(AppTheme.current.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: AppTheme.current.gradient,
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
        VStack(spacing: 20) {
            Spacer()

            // Video Thumbnail preview with subtle glow
            if let image = thumbnailImage {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.current.accent.opacity(0.35), radius: 16, y: 4)

                    // Duration badge
                    if videoDuration > 0 {
                        Text(formatDuration(videoDuration))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
            }

            // Progress Section
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: kProgressStrokeWidth)

                Circle()
                    .trim(from: 0, to: viewModel.exportEngine.progress)
                    .stroke(
                        LinearGradient(
                            colors: AppTheme.current.vividGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: kProgressStrokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: viewModel.exportEngine.progress)

                VStack(spacing: 2) {
                    Text("\(Int(viewModel.exportEngine.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(.white)

                    Text("Exporting...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: kProgressCircleSize, height: kProgressCircleSize)

            // Export Info Chip
            HStack(spacing: 8) {
                Label(
                    viewModel.selectedPreset.displayName.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? "Video",
                    systemImage: viewModel.selectedPreset.iconName
                )
                Text("•")
                    .foregroundColor(.secondary)
                Text(viewModel.settings.quality.rawValue)
                Text("•")
                    .foregroundColor(.secondary)
                Text(project.selectedStyle.name)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Capsule())

            Spacer()

            Button("Cancel Export") {
                showCancelAlert = true
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, kSectionPadding)
    }

    // MARK: - State 3: Complete

    /// Why this screen is a `ScrollView` and not the `VStack` with a `Spacer`
    /// at each end that it used to be.
    ///
    /// The old column had 549pt of fixed content. An iPhone SE content area is
    /// 603pt, so each `Spacer` got 27pt and the screen was already 91% full —
    /// while a Pro Max had 246pt of slack for the same content to float in.
    /// That is the "everything compacted in the centre" the owner reported:
    /// one fixed cluster, sized for the smallest phone, shown on every phone.
    ///
    /// So: the hero takes a share of the viewport rather than a constant;
    /// the summary card fills the width instead of hugging four columns; the
    /// content scrolls when it cannot fit, which is the only honest answer at
    /// the larger accessibility text sizes; and the buttons are pinned with
    /// `safeAreaInset` so "Done" is reachable without scrolling to it,
    /// whatever the content above does.
    private var completedView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    successHero(
                        height: ExportCompletionLayout.heroHeight(forViewportHeight: proxy.size.height)
                    )

                    successTitle

                    ExportSummaryRow(
                        format: viewModel.selectedPreset.displayName
                            .components(separatedBy: "/").first?
                            .trimmingCharacters(in: .whitespaces) ?? "Video",
                        duration: formatDuration(videoDuration),
                        style: project.selectedStyle.name
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, kSectionPadding)
                .padding(.vertical, 24)
                // Fill the screen when the content is shorter than it, so the
                // column is centred in the space it has rather than stacked at
                // the top of it. When the content is taller this does nothing
                // and the view scrolls.
                .frame(
                    minHeight: max(0, proxy.size.height - ExportCompletionLayout.footerReserve),
                    alignment: .center
                )
            }
            // No rubber-banding on a screen whose content usually fits.
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                ExportCompletionFooter(
                    onShare: { showShareSheet = true },
                    onDone: { dismiss() }
                )
                .padding(.horizontal, kSectionPadding)
                .background(Color.black)
            }
        }
    }

    private func successHero(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: height * ExportCompletionLayout.heroAspectRatio, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Color.green.opacity(0.2), radius: 20, y: 6)
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .background(Circle().fill(.black))
                .offset(x: 8, y: -8)
        }
    }

    private var successTitle: some View {
        VStack(spacing: 6) {
            Text("Export Complete!")
                .font(.title2.bold())
                .foregroundColor(.white)

            // The render is kept even when Photos refused it, so this line
            // must say which of the two happened.
            let saved = viewModel.exportEngine.savedToPhotoLibrary
            HStack(spacing: 6) {
                Image(systemName: saved ? "photo.on.rectangle" : "exclamationmark.triangle.fill")
                    .foregroundColor(saved ? .green : .yellow)
                Text(saved ? "Saved to Photo Library" : "Not saved to Photos — use Share to keep it")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, kSectionPadding)
    }

    private func loadVideoInfo() {
        guard let url = project.videoURL else { return }

        // Use cached thumbnail from project if available
        if let data = project.thumbnailData, let image = UIImage(data: data) {
            thumbnailImage = image
        }

        let asset = AVURLAsset(url: url)
        Task {
            let duration = try? await asset.load(.duration)
            if let d = duration {
                videoDuration = CMTimeGetSeconds(d)
            }

            // If no cached thumbnail, generate from asset with proper orientation
            if thumbnailImage == nil {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                if let (cgImage, _) = try? await generator.image(at: .zero) {
                    thumbnailImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
                .foregroundColor(isSelected ? AppTheme.current.accent : .gray)
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
                    .foregroundColor(AppTheme.current.accent)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: kCardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: kCardCornerRadius)
                .stroke(isSelected ? AppTheme.current.accent : .clear, lineWidth: 2)
        )
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
