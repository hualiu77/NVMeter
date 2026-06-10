import Foundation
import Yams

public struct BridgeEntry: Codable, Sendable {
    public let bridge: String
    public let vendor: String?
    public let usb_ids: [String]?
    public let smartctl_args: [String]
    public let verified_by: [String]?
    public let notes: String?
}

public struct BridgeDatabase: Sendable {
    public let entries: [BridgeEntry]

    public init(entries: [BridgeEntry]) { self.entries = entries }

    public static let empty = BridgeDatabase(entries: [])

    /// Load every YAML under `directory`, recursing into subdirectories
    /// (the drivedb repo keeps hand-verified entries at the top level and
    /// smartmontools imports under `imported/`). Top-level entries are
    /// loaded LAST so they win any USB-ID collision against imports.
    public static func load(directory: URL) throws -> BridgeDatabase {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return .empty
        }
        var topLevel: [URL] = []
        var nested: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "yaml" || url.pathExtension == "yml" else { continue }
            if url.deletingLastPathComponent().path == directory.path {
                topLevel.append(url)
            } else {
                nested.append(url)
            }
        }
        let decoder = YAMLDecoder()
        var entries: [BridgeEntry] = []
        for url in nested + topLevel {   // top-level last = wins in lookup-by-last
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let entry = try? decoder.decode(BridgeEntry.self, from: text)
            else { continue }
            entries.append(entry)
        }
        return BridgeDatabase(entries: entries)
    }

    /// Search standard locations and load the first that exists:
    ///   1. `~/Library/Application Support/NVMeter/bridges/` — user override
    ///      (clone NVMeter-drivedb there to get updates without an app update)
    ///   2. `<app bundle>/Contents/Resources/bridges/` — snapshot embedded at build time
    public static func loadDefault() -> BridgeDatabase {
        var candidates: [URL] = []
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) {
            candidates.append(support.appendingPathComponent("NVMeter/bridges", isDirectory: true))
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("bridges", isDirectory: true))
        }
        for dir in candidates {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let db = try? load(directory: dir), !db.entries.isEmpty {
                return db
            }
        }
        return .empty
    }

    /// Exact USB-ID lookup. Later entries win (see `load`).
    public func lookup(usbID: String) -> BridgeEntry? {
        let needle = usbID.lowercased()
        return entries.last { ($0.usb_ids ?? []).contains { $0.lowercased() == needle } }
    }

    public func lookup(usbVendor: String, product: String) -> BridgeEntry? {
        lookup(usbID: "\(usbVendor):\(product)")
    }
}
