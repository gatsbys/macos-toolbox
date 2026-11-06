import AppKit
import Observation

@MainActor @Observable
final class ClipboardCopyFeedback {
    static let preferenceKey = "tools.clipboard-history.copySoundEnabled"
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.preferenceKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let playSound: () -> Void

    init(defaults: UserDefaults = .standard, playSound: (() -> Void)? = nil) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        if let playSound { self.playSound = playSound }
        else {
            let sound = Self.makeSound()
            self.playSound = {
                if sound?.isPlaying == true { sound?.stop() }
                sound?.play()
            }
        }
    }

    static func makeSound() -> NSSound? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "Copy", withExtension: "wav") else { return nil }
        // The short waveform includes its attenuation, matching the preview.
        return NSSound(contentsOf: url, byReference: false)
    }

    /// Called after a successful capture or write, never from loading history.
    func didCopy() {
        guard isEnabled else { return }
        playSound()
    }
}
