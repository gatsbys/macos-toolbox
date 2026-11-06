import Foundation
import Testing
@testable import ToolboxCore

@MainActor
private final class PermissionProbe {
    var trusted = false
    var prompts = 0
    var settingsOpened = 0
    var client: AccessibilityPermissionClient {
        AccessibilityPermissionClient(isTrusted: { self.trusted }, requestSystemPrompt: { self.prompts += 1 }, openSettings: { self.settingsOpened += 1 })
    }
}

@Test @MainActor func permissionRequestHasOnlyOneNavigationPath() {
    let probe = PermissionProbe()
    let service = PermissionService(client: probe.client)
    service.request()
    #expect(probe.prompts == 1)
    #expect(probe.settingsOpened == 0, "The system prompt owns navigation to Settings; do not also open the pane.")
    #expect(!service.isTrusted)
    service.monitor(whileEnabled: false)
}

@Test @MainActor func permissionRefreshReflectsGrantAndRevocationOnce() {
    let probe = PermissionProbe()
    let service = PermissionService(client: probe.client)
    var changes: [Bool] = []
    service.onChange = { changes.append($0) }
    probe.trusted = true
    service.refresh()
    service.refresh()
    #expect(service.isTrusted)
    #expect(changes == [true])
    probe.trusted = false
    service.refresh()
    #expect(!service.isTrusted)
    #expect(changes == [true, false])
    #expect(probe.prompts == 0 && probe.settingsOpened == 0)
}

@Test @MainActor func grantedPermissionDoesNotRequestAnotherPrompt() {
    let probe = PermissionProbe()
    probe.trusted = true
    let service = PermissionService(client: probe.client)
    service.request()
    #expect(probe.prompts == 0)
    #expect(probe.settingsOpened == 1)
    service.monitor(whileEnabled: false)
}

@Test @MainActor func repeatedClickCannotOpenASecondPermissionFlow() {
    let probe = PermissionProbe()
    let service = PermissionService(client: probe.client)
    service.request()
    service.request()
    service.openAccessibilitySettings()
    #expect(probe.prompts == 1)
    #expect(probe.settingsOpened == 0)
    #expect(service.isRequestInFlight)
}

@Test @MainActor func subsequentExplicitRequestOpensSettingsWithoutAnotherPrompt() async throws {
    let probe = PermissionProbe()
    let service = PermissionService(client: probe.client)
    service.request()

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while service.isRequestInFlight && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
    }
    try #require(!service.isRequestInFlight, "The permission request cooldown did not finish.")

    service.request()
    #expect(probe.prompts == 1)
    #expect(probe.settingsOpened == 1)
}

@Test @MainActor func returningAfterGrantUpdatesPermissionWithoutRequestingAgain() {
    let probe = PermissionProbe()
    let service = PermissionService(client: probe.client)
    var changes: [Bool] = []
    service.onChange = { changes.append($0); service.monitor(whileEnabled: $0) }
    service.monitor(whileEnabled: true)
    service.request()
    probe.trusted = true
    service.refresh()
    service.refresh()
    #expect(service.isTrusted)
    #expect(changes == [true])
    #expect(probe.prompts == 1 && probe.settingsOpened == 0)
    service.monitor(whileEnabled: false)
    service.onChange = nil
}
