import Foundation

// MARK: - Analytics Provider Protocol

/// Protocol for swappable analytics backends (Firebase, custom, etc.)
protocol AnalyticsProvider {
    func logEvent(_ name: String, parameters: [String: Any]?)
}

// MARK: - AnalyticsService

/// Lightweight analytics wrapper. Only 5 events — no complex tracking.
final class AnalyticsService {
    static let shared = AnalyticsService()

    /// Set this to a Firebase or custom provider in app init
    var provider: AnalyticsProvider?

    private init() {}

    // MARK: - Events

    /// Logged when a video is imported from Photo Library
    static func videoImported(duration: Double) {
        shared.provider?.logEvent("video_imported", parameters: [
            "duration_seconds": duration,
        ])
    }

    /// Logged when captions are generated via speech recognition
    static func captionsGenerated(wordCount: Int) {
        shared.provider?.logEvent("captions_generated", parameters: [
            "word_count": wordCount,
        ])
    }

    /// Logged when a video is exported
    static func exportCompleted(preset: String, isPro: Bool) {
        shared.provider?.logEvent("export_completed", parameters: [
            "preset": preset,
            "is_pro": isPro,
        ])
    }

    /// Logged when the paywall is shown to the user
    static func paywallShown(trigger: String) {
        shared.provider?.logEvent("paywall_shown", parameters: [
            "trigger": trigger,
        ])
    }

    /// Logged when a purchase is completed
    static func purchaseCompleted(productID: String) {
        shared.provider?.logEvent("purchase_completed", parameters: [
            "product_id": productID,
        ])
    }
}
