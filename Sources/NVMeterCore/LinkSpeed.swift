import Foundation

/// Theoretical maximum throughput of a drive's link, used as a reference
/// bar next to measured results. This is a *link* ceiling — the actual
/// speed is gated by protocol overhead, the enclosure bridge chip, the
/// cable, and the drive itself, so real numbers are always lower.
public struct LinkSpeed: Sendable, Equatable {
    public let maxMBps: Double
    public let label: String      // "PCIe 4.0 ×4" / "USB 10 Gbps"
    public init(maxMBps: Double, label: String) {
        self.maxMBps = maxMBps
        self.label = label
    }
}

public enum LinkSpeedProbe {
    /// Best-effort: NVMe controllers expose a PCIe link in SPNVMeDataType;
    /// USB bridges expose a link speed in IORegistry. Returns nil for the
    /// internal Apple SSD (Apple Fabric publishes no comparable figure).
    public static func probe(modelName: String?, bus: DeviceFacts.Bus) -> LinkSpeed? {
        guard let model = modelName?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return nil }
        if let pcie = pcie(model: model) { return pcie }
        if bus == .usb, let usb = usb(productMatching: model) { return usb }
        return nil
    }

    // MARK: - PCIe (NVMe controllers, incl. Thunderbolt pass-through)

    private static func pcie(model: String) -> LinkSpeed? {
        guard let data = run("/usr/sbin/system_profiler", ["-json", "SPNVMeDataType"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let top = json["SPNVMeDataType"] as? [[String: Any]] else { return nil }

        func search(_ items: [[String: Any]]) -> LinkSpeed? {
            for it in items {
                if let name = it["_name"] as? String,
                   matches(name, model),
                   let speed = it["spnvme_linkspeed"] as? String,
                   let width = it["spnvme_linkwidth"] as? String,
                   let computed = compute(speed: speed, width: width) {
                    return computed
                }
                if let sub = it["_items"] as? [[String: Any]], let r = search(sub) { return r }
            }
            return nil
        }
        return search(top)
    }

    private static func compute(speed: String, width: String) -> LinkSpeed? {
        // speed "16.0 GT/s" · width "x4"
        let gts = Double(speed.split(separator: " ").first.map(String.init) ?? "") ?? 0
        let lanes = Int(width.lowercased().replacingOccurrences(of: "x", with: "")) ?? 0
        guard gts > 0, lanes > 0 else { return nil }

        let perLane: Double      // MB/s per lane (post-encoding)
        let gen: String
        switch gts {
        case 2.5:  perLane = 250;    gen = "1.0"
        case 5.0:  perLane = 500;    gen = "2.0"
        case 8.0:  perLane = 984.6;  gen = "3.0"   // 128b/130b
        case 16.0: perLane = 1969;   gen = "4.0"
        case 32.0: perLane = 3938;   gen = "5.0"
        case 64.0: perLane = 7563;   gen = "6.0"
        default:   perLane = gts / 8 * 0.985 * 1000; gen = String(format: "%.1f", gts)
        }
        return LinkSpeed(maxMBps: perLane * Double(lanes), label: "PCIe \(gen) ×\(lanes)")
    }

    // MARK: - USB bridges

    private static func usb(productMatching model: String) -> LinkSpeed? {
        guard let data = run("/usr/sbin/ioreg", ["-r", "-c", "IOUSBHostDevice", "-d", "1", "-a"]),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return nil }
        for node in plist {
            guard let name = node["USB Product Name"] as? String, matches(name, model),
                  let bps = (node["UsbLinkSpeed"] as? NSNumber)?.doubleValue, bps > 0 else { continue }
            let gbps = bps / 1e9
            // Effective bytes/s ≈ bps / 10 (8b/10b + protocol overhead);
            // a fair real-world ceiling for USB mass storage.
            let mbps = bps / 10 / 1e6
            return LinkSpeed(maxMBps: mbps, label: String(format: "USB %.0f Gbps", gbps))
        }
        return nil
    }

    // MARK: - Helpers

    private static func matches(_ a: String, _ b: String) -> Bool {
        let la = a.lowercased(), lb = b.lowercased()
        return la == lb || la.contains(lb) || lb.contains(la)
    }

    private static func run(_ exe: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        return out.fileHandleForReading.readDataToEndOfFile()
    }
}
