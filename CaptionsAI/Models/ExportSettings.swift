import AVFoundation
import CoreGraphics

// MARK: - ExportResolution

/// Resolution options for video export.
enum ExportResolution: String, CaseIterable, Identifiable, Codable {
    case original  = "Original"
    case hd720     = "720p"
    case full1080  = "1080p"
    case uhd4K     = "4K"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .hd720:    return "720p HD"
        case .full1080: return "1080p Full HD"
        case .uhd4K:    return "4K Ultra HD"
        }
    }

    /// Multiplier applied to the base video size for resolution scaling.
    var multiplier: CGFloat {
        switch self {
        case .original: return 1.0
        case .hd720:    return 0.667
        case .full1080: return 1.0
        case .uhd4K:    return 2.0
        }
    }
}

// MARK: - ExportQuality

/// Quality tier that maps to an AVAssetExportSession preset.
enum ExportQuality: String, CaseIterable, Identifiable, Codable {
    case medium  = "Medium"
    case high    = "High"
    case maximum = "Maximum"

    var id: String { rawValue }

    /// Maps to an AVAssetExportSession preset name.
    var exportPreset: String {
        switch self {
        case .medium:  return AVAssetExportPresetMediumQuality
        case .high:    return AVAssetExportPreset1920x1080
        case .maximum: return AVAssetExportPresetHighestQuality
        }
    }

    /// Multiplier for estimating output file size.
    var bitrateMultiplier: Double {
        switch self {
        case .medium:  return 0.5
        case .high:    return 1.0
        case .maximum: return 1.8
        }
    }
}

// MARK: - ExportCodec

/// Video codec options for export.
enum ExportCodec: String, CaseIterable, Identifiable, Codable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"

    var id: String { rawValue }

    var exportPreset: String {
        switch self {
        case .h264: return AVAssetExportPresetHighestQuality
        case .h265: return AVAssetExportPresetHEVCHighestQuality
        }
    }

    /// HEVC is ~40% more efficient than H.264 at similar quality.
    var bitrateMultiplier: Double {
        switch self {
        case .h264: return 1.0
        case .h265: return 0.6
        }
    }
}

// MARK: - ExportSettings

/// Aggregated export configuration chosen by the user.
struct ExportSettings {
    var resolution: ExportResolution = .full1080
    var quality: ExportQuality = .high
    var codec: ExportCodec = .h264
    var includeAudio: Bool = true

    // MARK: - File Size Estimation

    /// Base bitrate in Mbps for 1080p H.264 High quality.
    private static let kBaseBitrateMbps: Double = 5.0

    /// Returns a human-readable estimated file size string (e.g. "~48 MB").
    func estimatedFileSize(durationSeconds: Double) -> String {
        let bitrateMbps = Self.kBaseBitrateMbps
            * Double(resolution.multiplier)
            * quality.bitrateMultiplier
            * codec.bitrateMultiplier
        let fileSizeMB = (bitrateMbps * durationSeconds) / 8.0

        if fileSizeMB >= 1000 {
            return String(format: "~%.1f GB", fileSizeMB / 1000)
        }
        return String(format: "~%.0f MB", fileSizeMB)
    }
}
