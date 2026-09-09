import Foundation
import SwiftData

// MARK: - WordTiming

/// Represents the timing for a single word within a caption segment.
struct WordTiming: Codable, Hashable, Identifiable {
    var id: String {
        "\(word)-\(startTime)"
    }

    var word: String
    var startTime: Double
    var endTime: Double

    var duration: Double {
        endTime - startTime
    }
}

// MARK: - CaptionSegment

/// A single caption segment with timestamp range and text content.
/// Contains word-level timing for word-by-word highlighting.
@Model
final class CaptionSegment {
    var id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    var sortOrder: Int

    /// Word-level timing data stored as JSON
    var wordsData: Data?

    /// Relationship back to parent project
    var project: Project?

    // MARK: - Computed Properties

    var duration: Double {
        endTime - startTime
    }

    var formattedTimeRange: String {
        "\(formatTime(startTime)) - \(formatTime(endTime))"
    }

    var words: [WordTiming] {
        get {
            guard let data = wordsData else { return [] }
            return (try? JSONDecoder().decode([WordTiming].self, from: data)) ?? []
        }
        set {
            wordsData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        text: String,
        sortOrder: Int = 0,
        words: [WordTiming] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.sortOrder = sortOrder
        wordsData = try? JSONEncoder().encode(words)
    }

    // MARK: - Helpers

    /// Returns the word that should be highlighted at the given time
    func activeWord(at time: Double) -> WordTiming? {
        words.first { time >= $0.startTime && time < $0.endTime }
    }

    /// Whether this segment is active at the given playback time
    func isActive(at time: Double) -> Bool {
        time >= startTime && time < endTime
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
