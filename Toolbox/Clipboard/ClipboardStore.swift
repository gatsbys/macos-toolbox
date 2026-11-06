import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardStoreError: Error, LocalizedError {
    case tooLarge, missing, invalidIndex
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Esta copia supera el límite de 25 MB y no se ha guardado."
        case .missing: "Esta entrada ya no está disponible."
        case .invalidIndex: "No se ha podido leer el historial. Los datos se han conservado para recuperarlos."
        }
    }
}

actor ClipboardStore {
    static let maximumStorageBytes = 250 * 1_024 * 1_024
    private let directory: URL
    private let budget: Int
    private var entries: [ClipboardEntry] = []
    private var loaded = false
    private struct Index: Codable { let version: Int; let entries: [ClipboardEntry] }

    init(directory: URL, budget: Int = maximumStorageBytes) { self.directory = directory; self.budget = budget }

    func load() throws -> [ClipboardEntry] {
        if loaded { return entries }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let indexURL = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            guard let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data), index.version == 1 else {
                throw ClipboardStoreError.invalidIndex
            }
            entries = index.entries.filter { FileManager.default.fileExists(atPath: payloadURL($0.id).path) }
        }
        loaded = true
        // A prior interrupted save/delete can leave orphaned payloads. Only remove
        // files in our UUID namespace after a valid index has been loaded.
        let ids = Set(entries.map { $0.id.uuidString })
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let stem = url.lastPathComponent.components(separatedBy: ".").first ?? ""
            if UUID(uuidString: stem) != nil && !ids.contains(stem) { try? FileManager.default.removeItem(at: url) }
        }
        return entries
    }

    func insert(_ content: ClipboardContent, sourceApp: String?, limit: Int, date: Date = .now) throws -> [ClipboardEntry] {
        _ = try load()
        guard !content.isEmpty else { return entries }
        guard content.byteCount <= ClipboardContent.maximumCopyBytes else { throw ClipboardStoreError.tooLarge }
        let fingerprint = content.fingerprint
        if let existing = entries.firstIndex(where: { $0.fingerprint == fingerprint }) {
            let old = entries
            var entry = entries.remove(at: existing)
            entry.copiedAt = date
            entry.sourceApp = sourceApp
            entries.insert(entry, at: 0)
            do { try saveIndex() } catch { entries = old; throw error }
            return entries
        }
        let id = UUID()
        let data = try JSONEncoder().encode(content)
        guard data.count <= budget else { throw ClipboardStoreError.tooLarge }
        let thumbnail = Self.thumbnail(for: content)
        try write(data, to: payloadURL(id))
        if let thumbnail { try write(thumbnail, to: thumbnailURL(id)) }
        let entry = ClipboardEntry(id: id, fingerprint: fingerprint, copiedAt: date, sourceApp: sourceApp, kind: content.kind,
                                   preview: content.preview, searchText: String(content.plainText.prefix(20_000)),
                                   byteCount: data.count + (thumbnail?.count ?? 0), hasThumbnail: thumbnail != nil)
        let old = entries
        entries.insert(entry, at: 0)
        let removed = trim(limit: limit)
        do { try saveIndex() } catch { entries = old; deleteFiles(id); throw error }
        removed.forEach { deleteFiles($0.id) }
        return entries
    }

    func content(for id: UUID) throws -> ClipboardContent {
        _ = try load()
        guard entries.contains(where: { $0.id == id }), let data = try? Data(contentsOf: payloadURL(id)),
              let content = try? JSONDecoder().decode(ClipboardContent.self, from: data) else { throw ClipboardStoreError.missing }
        return content
    }

    func thumbnail(for id: UUID) -> Data? { try? Data(contentsOf: thumbnailURL(id)) }

    func setLimit(_ limit: Int) throws -> [ClipboardEntry] {
        _ = try load()
        let old = entries
        let removed = trim(limit: limit)
        do { try saveIndex() } catch { entries = old; throw error }
        removed.forEach { deleteFiles($0.id) }
        return entries
    }

    func remove(_ id: UUID) throws -> [ClipboardEntry] {
        _ = try load()
        let old = entries
        entries.removeAll { $0.id == id }
        do { try saveIndex() } catch { entries = old; throw error }
        deleteFiles(id)
        return entries
    }

    func clear() throws -> [ClipboardEntry] {
        _ = try load()
        let old = entries
        entries = []
        do { try saveIndex() } catch { entries = old; throw error }
        old.forEach { deleteFiles($0.id) }
        return entries
    }

    private func trim(limit: Int) -> [ClipboardEntry] {
        var removed: [ClipboardEntry] = []
        var total = entries.reduce(0) { $0 + $1.byteCount }
        while entries.count > max(1, limit) || total > budget {
            let entry = entries.removeLast()
            total -= entry.byteCount
            removed.append(entry)
        }
        return removed
    }
    private func payloadURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func thumbnailURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".png") }
    private func deleteFiles(_ id: UUID) { try? FileManager.default.removeItem(at: payloadURL(id)); try? FileManager.default.removeItem(at: thumbnailURL(id)) }
    private func saveIndex() throws { try write(JSONEncoder().encode(Index(version: 1, entries: entries)), to: directory.appendingPathComponent("index.json")) }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func thumbnail(for content: ClipboardContent) -> Data? {
        let images = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
        guard let rep = content.items.flatMap(\.representations).first(where: { images.contains($0.type) }),
              let source = CGImageSourceCreateWithData(rep.data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 220, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
}
