import AppKit
import Foundation

// Invoked by dev.sh, after signature verification. Never force-kill an app.
let fileManager = FileManager.default
let developmentID = "com.cristian.Toolbox.debug"
let toolboxIDs = [developmentID, "com.cristian.Toolbox"]

func install() throws {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "ToolboxInstall", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Falta la app compilada."])
    }
    let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let applications = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    let destination = applications.appendingPathComponent("Toolbox Dev.app", isDirectory: true)
    guard Bundle(url: source)?.bundleIdentifier == developmentID else {
        throw NSError(domain: "ToolboxInstall", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Solo se puede instalar la compilación Debug de Toolbox."])
    }
    let hasPrevious = fileManager.fileExists(atPath: destination.path)
    if hasPrevious && Bundle(url: destination)?.bundleIdentifier != developmentID {
        throw NSError(domain: "ToolboxInstall", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Hay otra aplicación en la ruta de destino; no se reemplazará."])
    }
    try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
    let staging = applications.appendingPathComponent(".Toolbox-install-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
    let next = staging.appendingPathComponent("Toolbox Dev.app", isDirectory: true)
    let previous = staging.appendingPathComponent("previous.app", isDirectory: true)
    defer {
        // A failed rollback must leave the only remaining old copy intact.
        if !fileManager.fileExists(atPath: previous.path) { try? fileManager.removeItem(at: staging) }
    }
    try fileManager.copyItem(at: source, to: next)

    let running = toolboxIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    for application in running { application.terminate() }
    let deadline = Date().addingTimeInterval(10)
    while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard running.allSatisfy(\.isTerminated) else {
        throw NSError(domain: "ToolboxInstall", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Toolbox no se ha cerrado. Ciérralo desde su menú y repite ./Scripts/dev.sh."])
    }
    if hasPrevious { try fileManager.moveItem(at: destination, to: previous) }
    do {
        try fileManager.moveItem(at: next, to: destination)
    } catch {
        if hasPrevious {
            do { try fileManager.moveItem(at: previous, to: destination) }
            catch {
                fputs("Copia anterior conservada en \(previous.path)\n", stderr)
            }
        }
        throw error
    }
    if hasPrevious { try fileManager.removeItem(at: previous) }
}

do { try install() }
catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
