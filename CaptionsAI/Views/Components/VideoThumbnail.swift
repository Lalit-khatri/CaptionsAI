import AVFoundation
import SwiftUI

// MARK: - VideoThumbnail

/// Async component that generates and displays a video thumbnail.
struct VideoThumbnail: View {
    let url: URL
    var cornerRadius: CGFloat = 12

    @State private var thumbnail: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Color.gray.opacity(0.2)
                ProgressView()
                    .tint(.gray)
            } else {
                Color.gray.opacity(0.2)
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            thumbnail = UIImage(cgImage: cgImage)
        } catch {
            thumbnail = nil
        }

        isLoading = false
    }
}
