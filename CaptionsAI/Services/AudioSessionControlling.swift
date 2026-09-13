import AVFoundation

// MARK: - AudioSessionControlling

/// The slice of `AVAudioSession` the editor uses.
///
/// `AVAudioSession.sharedInstance()` is process-wide and shared with every
/// other app on the device, so a test that drove the real one would be both
/// unable to observe it and rude to whatever else is playing. The two methods
/// below are declared exactly as `AVAudioSession` declares them, which is why
/// the conformance is empty.
protocol AudioSessionControlling: AnyObject {
    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionControlling {}
