import AppKit
import Foundation
import Testing
@testable import ToolboxCore

@Test @MainActor func copyFeedbackPlaysForSuccessfulCopyEvents() throws {
    let suite = "ToolboxCopyFeedbackTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var played = 0
    let feedback = ClipboardCopyFeedback(defaults: defaults) { played += 1 }
    #expect(feedback.isEnabled)
    #expect(played == 0)
    feedback.didCopy()
    feedback.didCopy()
    #expect(played == 2)
}

@Test @MainActor func mutedCopyFeedbackPersistsAcrossInstances() throws {
    let suite = "ToolboxCopyFeedbackTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var played = 0
    let feedback = ClipboardCopyFeedback(defaults: defaults) { played += 1 }
    feedback.isEnabled = false
    feedback.didCopy()
    let reopened = ClipboardCopyFeedback(defaults: defaults) { played += 1 }
    #expect(!reopened.isEnabled)
    reopened.didCopy()
    #expect(played == 0)
}

@Test @MainActor func copyFeedbackCanBeEnabledAgain() throws {
    let suite = "ToolboxCopyFeedbackTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var played = 0
    let feedback = ClipboardCopyFeedback(defaults: defaults) { played += 1 }
    feedback.isEnabled = false
    feedback.didCopy()
    feedback.isEnabled = true
    feedback.didCopy()
    #expect(played == 1)
    #expect(defaults.bool(forKey: ClipboardCopyFeedback.preferenceKey))
}

@Test @MainActor func bundledCopyConfirmationSoundIsAvailable() throws {
    let sound = try #require(ClipboardCopyFeedback.makeSound())
    #expect(sound.duration > 0)
    #expect(sound.duration < 0.2)
}
