// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ToolboxCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ToolboxCore", targets: ["ToolboxCore"])],
    targets: [
        .target(name: "ToolboxCore", path: "Toolbox", exclude: ["App/ToolModule.swift", "App/ToolboxApp.swift", "Clipboard/ClipboardHistoryTool.swift", "Clipboard/ClipboardPanelController.swift", "Clipboard/ClipboardHistoryView.swift", "Clipboard/ClipboardSettingsView.swift", "Clipboard/ShortcutRecorder.swift", "Interface", "Info.plist", "Resources/Toolbox.icns", "WindowSnapping/MouseMonitor.swift", "WindowSnapping/PreviewPanel.swift", "WindowSnapping/WindowSnapTool.swift"], sources: ["Core", "Clipboard/ClipboardCopyFeedback.swift", "Clipboard/ClipboardPasteController.swift", "Clipboard/ClipboardModels.swift", "Clipboard/ClipboardStore.swift", "Clipboard/ClipboardPasteboard.swift", "Clipboard/ClipboardHotKey.swift", "App/PermissionService.swift", "WindowSnapping/AXWindowAccess.swift", "WindowSnapping/SnapEngine.swift"], resources: [.copy("Resources/Copy.wav")]),
        .testTarget(name: "ToolboxCoreTests", dependencies: ["ToolboxCore"], path: "Tests")
    ]
)
