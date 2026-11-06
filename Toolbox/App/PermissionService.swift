import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor
struct AccessibilityPermissionClient {
    var isTrusted: () -> Bool
    var requestSystemPrompt: () -> Void
    var openSettings: () -> Void

    static var live: Self {
        Self(
            isTrusted: { AXIsProcessTrusted() },
            requestSystemPrompt: {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            },
            openSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}

@MainActor @Observable
final class PermissionService {
    private(set) var isTrusted: Bool
    private(set) var hasRequestedPermission = false
    private(set) var isRequestInFlight = false
    var onChange: ((Bool) -> Void)?
    @ObservationIgnored private let client: AccessibilityPermissionClient
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var requestCooldown: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(client: AccessibilityPermissionClient = .live) {
        self.client = client
        isTrusted = client.isTrusted()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let trusted = client.isTrusted()
        if trusted != isTrusted { isTrusted = trusted; onChange?(trusted) }
    }

    var actionTitle: String {
        isTrusted || hasRequestedPermission ? "Abrir Accesibilidad…" : "Dar permiso…"
    }

    func request() {
        guard !isRequestInFlight else { return }
        refresh()
        beginRequestCooldown()
        if isTrusted || hasRequestedPermission {
            client.openSettings()
        } else {
            hasRequestedPermission = true
            // macOS presents this asynchronously and owns the "Open Settings"
            // action. Opening the pane ourselves here races that system dialog.
            client.requestSystemPrompt()
        }
    }

    func openAccessibilitySettings() {
        guard !isRequestInFlight else { return }
        beginRequestCooldown()
        client.openSettings()
    }

    func monitor(whileEnabled enabled: Bool) {
        guard enabled else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }
        // Idempotent: an onChange callback may reconcile the tool while this
        // very task is refreshing permission. Do not cancel/recreate it there.
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.refresh()
            }
        }
    }

    private func beginRequestCooldown() {
        isRequestInFlight = true
        requestCooldown?.cancel()
        requestCooldown = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            self?.isRequestInFlight = false
        }
    }
}
