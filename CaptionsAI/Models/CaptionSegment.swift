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

    /// The last decode, and the bytes it came from.
    ///
    /// `@Transient` because this is derived from ``wordsData``, which is the
    /// stored form. Keying on the data rather than a dirty flag means the
    /// cache is still correct if ``wordsData`` is replaced by SwiftData
    /// loading the row, not just by the setter below.
    @Transient private var decoded: [WordTiming]?
    @Transient private var decodedFrom: Data?

    /// How many times the JSON has actually been parsed, process-wide.
    ///
    /// This exists to be asserted on. The defect this cache fixes was not a
    /// wrong answer — `words` always returned the right timings — it was that
    /// it re-parsed them on every read, once per frame for the whole of an
    /// export. Nothing about the returned value can show that; only a count
    /// can. See `WordTimingCacheTests`.
    static var parseCount = 0

    var words: [WordTiming] {
        get {
            guard let data = wordsData else { return [] }
            if let decoded, decodedFrom == data { return decoded }

            let words = (try? JSONDecoder().decode([WordTiming].self, from: data)) ?? []
            Self.parseCount += 1
            decoded = words
            decodedFrom = data
            return words
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            wordsData = data
            decoded = newValue
            decodedFrom = data
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
