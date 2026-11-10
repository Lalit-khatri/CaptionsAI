import Foundation

// MARK: - CaptionGrouping

/// Splits a stream of timed words into the captions shown on screen.
///
/// Shared by every recogniser so that a clip reads the same however it was
/// transcribed: a caption ends after `maxWords` words, or once it spans
/// `maxDuration` seconds, whichever comes first.
enum CaptionGrouping {
    static let maxWords = 8
    static let maxDuration: Double = 4.0

    static func segments(from words: [WordTiming]) -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        var currentWords: [WordTiming] = []
        var segmentStartTime: Double = 0

        for (index, word) in words.enumerated() {
            if currentWords.isEmpty {
                segmentStartTime = word.startTime
            }
            currentWords.append(word)

            let duration = word.endTime - segmentStartTime
            let isLastWord = index == words.count - 1

            if currentWords.count >= maxWords || duration >= maxDuration || isLastWord {
                segments.append(
                    CaptionSegment(
                        startTime: segmentStartTime,
                        endTime: word.endTime,
                        text: currentWords.map(\.word).joined(separator: " "),
                        sortOrder: segments.count,
                        words: currentWords
                    )
                )
                currentWords = []
            }
        }

        return segments
    }
}
