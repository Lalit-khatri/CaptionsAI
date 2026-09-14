import AVFoundation
import CoreGraphics

// MARK: - ExportResolution

/// Resolution options for video export.
enum ExportResolution: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case hd720 = "720p"
    case full1080 = "1080p"
    case uhd4K = "4K"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .hd720: return "720p HD"
        case .full1080: return "1080p Full HD"
        case .uhd4K: return "4K Ultra HD"
        }
    }

    /// The number of lines this setting names, or `nil` for `.original`,
    /// which means "whatever came in".
    ///
    /// It is the **short** side that is named, not the height, so a portrait
    /// 1080×1920 clip counts as 1080p exactly like the landscape 1920×1080 clip
    /// it was rotated from.
    var targetShortSide: CGFloat? {
        switch self {
        case .original: return nil
        case .hd720: return 720
        case .full1080: return 1080
        case .uhd4K: return 2160
        }
    }

    /// The size to render at, given the canvas the chosen format implies.
    ///
    /// These names are absolute targets, not scale factors. Treating them as
    /// scale factors is what made "4K" mean *twice whatever you already had* —
    /// so a 4K source exported at 4K came out at 7680×4320, and "720p" on the
    /// same source came out at 2562×1440, which is not 720p and not even a
    /// multiple of 16.
    ///
    /// Upscaling is allowed: asking a 1080p source for 4K cannot add detail,
    /// but it is an explicit choice and the app offers it. What is not allowed
    /// is the number meaning something different depending on the input.
    func outputSize(for canvas: CGSize) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return canvas }
        guard let target = targetShortSide else { return Self.evenSize(canvas) }

        let shortSide = min(canvas.width, canvas.height)
        let scale = target / shortSide
        return Self.evenSize(CGSize(width: canvas.width * scale, height: canvas.height * scale))
    }

    /// H.264 requires even dimensions, and odd ones survive surprisingly far
    /// into the pipeline before failing, so every path out of ``outputSize``
    /// goes through here.
    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, (size.width / 2).rounded() * 2),
            height: max(2, (size.height / 2).rounded() * 2)
        )
    }
}

// MARK: - ExportQuality

/// Quality tier that maps to an AVAssetExportSession preset.
///
/// Only tiers that AVFoundation can actually deliver differently are offered.
/// There used to be a third, `Maximum`, and it encoded byte-identically to
/// `High`: the candidate race in ``ExportEngine`` tried the *codec* preset
/// first, `.h264` maps to `AVAssetExportPresetHighestQuality`, and that is
/// always compatible — so it always won and the picker moved nothing but the
/// estimate. Apple ships no H.264 tier between "medium" and "highest", so the
/// honest fix is two tiers that differ rather than three that do not.
enum ExportQuality: String, CaseIterable, Identifiable, Codable {
    case medium = "Medium"
    case high = "High"

    var id: String {
        rawValue
    }

    /// The encoder preset for this tier within `codec`'s family.
    ///
    /// The codec decides the *family*, the quality decides the *tier*. Taking
    /// both from one flat candidate list is what let the codec silently
    /// overrule the quality.
    ///
    /// Deliberately never a resolution preset for H.264. `.high` used to map
    /// to `AVAssetExportPreset1920x1080`, which is a *size* ceiling wearing a
    /// quality label: picking 4K and High produced a 1080p file. Resolution is
    /// ``ExportResolution``'s decision and nothing here may overrule it.
    ///
    /// HEVC is the exception, and knowingly so: Apple ships no open-ended
    /// medium HEVC preset, so the medium HEVC tier is `HEVC1920x1080` and does
    /// carry a 1080p ceiling. That path is unreachable today — the codec
    /// picker is commented out and the codec is pinned to H.264 — and this
    /// note is here so that re-enabling it is a decision rather than a
    /// surprise.
    func exportPreset(for codec: ExportCodec) -> String {
        switch (codec, self) {
        case (.h264, .medium): return AVAssetExportPresetMediumQuality
        case (.h264, .high): return AVAssetExportPresetHighestQuality
        case (.h265, .medium): return AVAssetExportPresetHEVC1920x1080
        case (.h265, .high): return AVAssetExportPresetHEVCHighestQuality
        }
    }

    /// Multiplier for estimating output file size.
    var bitrateMultiplier: Double {
        switch self {
        case .medium: return 0.5
        case .high: return 1.0
        }
    }
}

// MARK: - ExportCodec

/// Video codec options for export.
enum ExportCodec: String, CaseIterable, Identifiable, Codable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"

    var id: String {
        rawValue
    }

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

    /// Rough bitrate weighting per resolution tier, for the size estimate only.
    ///
    /// Deliberately *not* derived from ``ExportResolution/outputSize(for:)``:
    /// the estimate is shown before a source is known, so it can only be a
    /// tier-based guess. Kept separate so nothing can mistake it for a geometry
    /// factor again — doing exactly that is what produced 8K exports.
    private var resolutionBitrateScale: Double {
        switch resolution {
        case .original: return 1.0
        case .hd720: return 0.667
        case .full1080: return 1.0
        case .uhd4K: return 2.0
        }
    }

    /// Returns a human-readable estimated file size string (e.g. "~48 MB").
    func estimatedFileSize(durationSeconds: Double) -> String {
        let bitrateMbps = Self.kBaseBitrateMbps
            * resolutionBitrateScale
            * quality.bitrateMultiplier
            * codec.bitrateMultiplier
        let fileSizeMB = (bitrateMbps * durationSeconds) / 8.0

        if fileSizeMB >= 1000 {
            return String(format: "~%.1f GB", fileSizeMB / 1000)
        }
        return String(format: "~%.0f MB", fileSizeMB)
    }
}
