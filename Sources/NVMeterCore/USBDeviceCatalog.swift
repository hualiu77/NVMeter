import Foundation

/// One USB device attached to the host, as seen by IOKit.
public struct USBDevice: Sendable, Equatable {
    public let productName: String
    public let vendorName: String?
    /// 4-digit lowercase hex, e.g. "0bda"
    public let vendorID: String
    /// 4-digit lowercase hex, e.g. "9210"
    public let productID: String

    public var usbID: String { "\(vendorID):\(productID)" }
}

/// Enumerates USB devices via `ioreg -a` (XML plist output — far more
/// robust than scraping the human-readable tree).
public enum USBDeviceCatalog {

    public static func enumerate() -> [USBDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-r", "-c", "IOUSBHostDevice", "-d", "1", "-a"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let nodes = plist as? [[String: Any]]
        else { return [] }

        return nodes.compactMap { node in
            guard let product = node["USB Product Name"] as? String,
                  let vid = node["idVendor"] as? Int,
                  let pid = node["idProduct"] as? Int
            else { return nil }
            return USBDevice(
                productName: product,
                vendorName: node["USB Vendor Name"] as? String,
                vendorID: String(format: "%04x", vid),
                productID: String(format: "%04x", pid)
            )
        }
    }

    /// Best-effort match of a disk's `MediaName` (from diskutil) to the
    /// USB device it lives behind. Bridges almost always report the same
    /// string in both places (e.g. "RTL9210B-CG", "Elements 25A3"), so an
    /// exact case-insensitive match is tried first, then substring both ways.
    public static func match(mediaName: String, in devices: [USBDevice]) -> USBDevice? {
        let needle = mediaName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        if let exact = devices.first(where: { $0.productName.lowercased() == needle }) {
            return exact
        }
        return devices.first {
            let hay = $0.productName.lowercased()
            return hay.contains(needle) || needle.contains(hay)
        }
    }
}
