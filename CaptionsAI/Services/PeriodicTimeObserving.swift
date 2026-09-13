import AVFoundation
import Foundation

// MARK: - PeriodicTimeObserving

/// Registration of a repeating playback callback.
///
/// This exists as a protocol because `AVPlayer` will not say how many periodic
/// observers it is carrying. "The editor registers exactly one, and takes it
/// away again" is only checkable through a seam like this one.
protocol PeriodicTimeObserving: AnyObject {
    /// Starts calling `handler` every `interval`, and returns a token that
    /// identifies the registration.
    func addPeriodicObserver(every interval: CMTime, handler: @escaping (CMTime) -> Void) -> Any

    /// Stops the registration identified by `token`.
    func removePeriodicObserver(_ token: Any)
}

extension AVPlayer: PeriodicTimeObserving {
    func addPeriodicObserver(every interval: CMTime, handler: @escaping (CMTime) -> Void) -> Any {
        addPeriodicTimeObserver(forInterval: interval, queue: .main, using: handler)
    }

    func removePeriodicObserver(_ token: Any) {
        removeTimeObserver(token)
    }
}
