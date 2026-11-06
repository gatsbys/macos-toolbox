import Foundation
import Testing
@testable import ToolboxCore

@MainActor
private final class PasteProbe {
    var trusted = true
    var running = true
    var activates = true
    var frontmost: pid_t? = 42
    var released = true
    var canPost = true
    var pauses = 0
    var events: [String] = []
    var onPause: (() throws -> Void)?
    var client: ClipboardPasteClient {
        ClipboardPasteClient(
            isTrusted: { self.trusted },
            isRunning: { _ in self.running },
            activate: { self.events.append("activate:\($0)"); return self.activates },
            frontmostPID: { self.frontmost },
            modifiersReleased: { self.released },
            postPaste: { self.events.append("paste:\($0)"); return self.canPost },
            pause: { self.pauses += 1; try self.onPause?() }
        )
    }
}

@MainActor
private func withPasteController(_ body: @MainActor (ClipboardPasteController, PasteProbe, UserDefaults) async throws -> Void) async throws {
    let name = "ToolboxPasteTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let probe = PasteProbe()
    let controller = ClipboardPasteController(defaults: defaults, client: probe.client)
    try await body(controller, probe, defaults)
}

@Test @MainActor func pasteSelectionIsOptInAndPersists() async throws {
    try await withPasteController { controller, probe, defaults in
        #expect(!controller.isEnabled)
        controller.isEnabled = true
        #expect(ClipboardPasteController(defaults: defaults, client: probe.client).isEnabled)
        controller.isEnabled = false
        #expect(!ClipboardPasteController(defaults: defaults, client: probe.client).isEnabled)
        #expect(probe.events.isEmpty)
    }
}

@Test @MainActor func pasteWaitsForPanelToReleaseFocusAndTargetsOriginalProcess() async throws {
    try await withPasteController { controller, probe, _ in
        try await controller.paste(to: 42)
        #expect(probe.pauses == 2)
        #expect(probe.events == ["activate:42", "paste:42"])
    }
}

@Test @MainActor func pasteWithoutPermissionNeverActivatesOrSendsKeys() async throws {
    try await withPasteController { controller, probe, _ in
        probe.trusted = false
        await #expect(throws: ClipboardPasteError.permission) { try await controller.paste(to: 42) }
        #expect(probe.events.isEmpty)
    }
}

@Test @MainActor func pasteRejectsMissingOrTerminatedDestination() async throws {
    try await withPasteController { controller, probe, _ in
        await #expect(throws: ClipboardPasteError.unavailable) { try await controller.paste(to: nil) }
        probe.running = false
        await #expect(throws: ClipboardPasteError.unavailable) { try await controller.paste(to: 42) }
        #expect(probe.events.isEmpty)
    }
}

@Test @MainActor func pasteWaitsForActivationAndReleasedModifiers() async throws {
    try await withPasteController { controller, probe, _ in
        probe.frontmost = 99
        probe.released = false
        probe.onPause = {
            if probe.pauses == 3 { probe.frontmost = 42 }
            if probe.pauses == 5 { probe.released = true }
        }
        try await controller.paste(to: 42)
        #expect(probe.pauses == 6)
        #expect(probe.events == ["activate:42", "paste:42"])
    }
}

@Test @MainActor func pasteNeverSendsToAnUnfocusedDestination() async throws {
    try await withPasteController { controller, probe, _ in
        probe.frontmost = 99
        await #expect(throws: ClipboardPasteError.focus) { try await controller.paste(to: 42) }
        #expect(probe.pauses == 40)
        #expect(probe.events == ["activate:42"])
    }
}

@Test @MainActor func pasteRequiresFocusToRemainStableBeforeSending() async throws {
    try await withPasteController { controller, probe, _ in
        probe.onPause = { if probe.pauses == 2 { probe.frontmost = 99 } }
        await #expect(throws: ClipboardPasteError.focus) { try await controller.paste(to: 42) }
        #expect(probe.events == ["activate:42"])
    }
}

@Test @MainActor func pasteDoesNotSendWhileModifierRemainsHeld() async throws {
    try await withPasteController { controller, probe, _ in
        probe.released = false
        await #expect(throws: ClipboardPasteError.focus) { try await controller.paste(to: 42) }
        #expect(probe.events == ["activate:42"])
    }
}

@Test @MainActor func pasteRechecksPermissionAndDestinationAfterWaiting() async throws {
    try await withPasteController { controller, probe, _ in
        probe.onPause = { probe.trusted = false }
        await #expect(throws: ClipboardPasteError.permission) { try await controller.paste(to: 42) }
        #expect(probe.events == ["activate:42"])
        probe.trusted = true
        probe.events = []
        probe.onPause = { probe.running = false }
        await #expect(throws: ClipboardPasteError.unavailable) { try await controller.paste(to: 42) }
        #expect(probe.events == ["activate:42"])
    }
}

@Test @MainActor func pasteReportsActivationAndEventFailures() async throws {
    try await withPasteController { controller, probe, _ in
        probe.activates = false
        await #expect(throws: ClipboardPasteError.focus) { try await controller.paste(to: 42) }
        #expect(probe.pauses == 0)
        probe.activates = true
        probe.canPost = false
        await #expect(throws: ClipboardPasteError.event) { try await controller.paste(to: 42) }
    }
}

@Test @MainActor func cancelledPasteDoesNotSendKeys() async throws {
    try await withPasteController { controller, probe, _ in
        probe.onPause = { throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await controller.paste(to: 42) }
        #expect(probe.events == ["activate:42"])
    }
}
