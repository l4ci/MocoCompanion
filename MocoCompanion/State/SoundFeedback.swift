import AppKit

/// Plays system sounds on timer lifecycle events.
/// All methods are safe to call from any context — NSSound handles its own threading.
enum SoundFeedback {
    /// Play a short, high-pitched beep on timer start/resume.
    static func playStart() {
        NSSound(named: "Tink")?.play()
    }

    /// Play a lower-pitched tone on timer stop/pause.
    static func playStop() {
        NSSound(named: "Pop")?.play()
    }
}
