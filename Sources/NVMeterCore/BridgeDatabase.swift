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

public struct BridgeDatabase {
    public let entries: [BridgeEntry]

    public init(entries: [BridgeEntry]) { self.entries = entries }

    public static func load(directory: URL) throws -> BridgeDatabase {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
        let decoder = YAMLDecoder()
        let entries = try urls.map { url -> BridgeEntry in
            let text = try String(contentsOf: url, encoding: .utf8)
            return try decoder.decode(BridgeEntry.self, from: text)
        }
        return BridgeDatabase(entries: entries)
    }

    public func lookup(usbVendor: String, product: String) -> BridgeEntry? {
        let needle = "\(usbVendor.lowercased()):\(product.lowercased())"
        return entries.first { ($0.usb_ids ?? []).map { $0.lowercased() }.contains(needle) }
    }
}
