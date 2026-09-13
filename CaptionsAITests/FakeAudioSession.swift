@testable import CaptionsAI
import AVFoundation
import Foundation

/// Records what the editor asks of the audio session instead of doing it.
///
/// The real `AVAudioSession` is a process-wide singleton shared with every
/// other app; driving it from a test would interrupt whatever the machine is
/// playing and still tell us nothing about what was asked for.
final class FakeAudioSession: AudioSessionControlling {
    struct Activation: Equatable {
        let active: Bool
        let options: AVAudioSession.SetActiveOptions
    }

    private(set) var category: AVAudioSession.Category?
    private(set) var mode: AVAudioSession.Mode?
    private(set) var activations: [Activation] = []

    /// Every `setActive` call in order, so a test can tell "released" from
    /// "released then claimed again".
    var isActive: Bool { activations.last?.active ?? false }

    var wasEverReleased: Bool { activations.contains { !$0.active } }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options _: AVAudioSession.CategoryOptions
    ) throws {
        self.category = category
        self.mode = mode
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activations.append(Activation(active: active, options: options))
    }
}
