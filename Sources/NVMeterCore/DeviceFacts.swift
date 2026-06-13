import Foundation

/// Extra context about a device beyond what `smartctl` reports — capacity,
/// usage, connection type, dock name, brand. Produced by `SystemProbe`.
public struct DeviceFacts: Sendable, Equatable {
    public enum Bus: String, Sendable, Equatable {
        case internalNVMe = "internal"      // Apple Fabric (built-in)
        case thunderbolt = "thunderbolt"    // PCIe-Express over TB
        case usb = "usb"                    // USB Mass Storage / NVMe
        case unknown = "unknown"
    }

    public var bus: Bus
    public var connectionLabel: String      // e.g. "Apple Fabric (internal)"
    public var dockName: String?            // e.g. "WERO TBT5 1M2-DOCK"
    public var brand: String?               // resolved from PCI vendor or model
    public var modelHint: String?           // diskutil MediaName, fallback when smartctl blocked
    public var capacityBytes: Int64
    public var usedBytes: Int64?
    public var powerOnHours: Int?
    public var lifetimeWrittenBytes: Int64?    // cumulative host writes
    public var mountPoints: [String]
    /// Bridge-database entry name matched by USB ID, if any. Set even for
    /// blocked devices — it lets the UI say "this enclosure is already in
    /// the community database" instead of asking for a report.
    public var knownBridgeName: String?
    /// The smartctl `-d` args that actually worked for this device, when
    /// the default open failed and a bridge-DB retry succeeded.
    public var workingSmartctlArgs: [String]?
    /// True for SD/CF card readers and other removable media. These have
    /// no SMART by design — the UI should say so neutrally instead of
    /// blaming macOS or soliciting a bridge report.
    public var isRemovableMedia: Bool        // e.g. ["/Volumes/1TNVME"]
    /// True = SSD, false = spinning HDD, nil = unknown. Drives the default
    /// for the random-4K test (pointless and slow on mechanical drives).
    public var isSolidState: Bool?

    public init(
        bus: Bus = .unknown,
        connectionLabel: String = "Unknown",
        dockName: String? = nil,
        brand: String? = nil,
        modelHint: String? = nil,
        capacityBytes: Int64 = 0,
        usedBytes: Int64? = nil,
        powerOnHours: Int? = nil,
        lifetimeWrittenBytes: Int64? = nil,
        mountPoints: [String] = [],
        knownBridgeName: String? = nil,
        workingSmartctlArgs: [String]? = nil,
        isRemovableMedia: Bool = false,
        isSolidState: Bool? = nil
    ) {
        self.bus = bus
        self.connectionLabel = connectionLabel
        self.dockName = dockName
        self.brand = brand
        self.modelHint = modelHint
        self.capacityBytes = capacityBytes
        self.usedBytes = usedBytes
        self.powerOnHours = powerOnHours
        self.lifetimeWrittenBytes = lifetimeWrittenBytes
        self.mountPoints = mountPoints
        self.knownBridgeName = knownBridgeName
        self.workingSmartctlArgs = workingSmartctlArgs
        self.isRemovableMedia = isRemovableMedia
        self.isSolidState = isSolidState
    }

    /// "1.0 TB" / "500.3 GB" etc — base-10 (SSD convention).
    public var capacityHuman: String { Self.humanBytes(capacityBytes) }

    /// "234.5 GB used of 1.0 TB" — nil if `usedBytes` unknown.
    public var usageHuman: String? {
        guard let used = usedBytes else { return nil }
        return "\(Self.humanBytes(used)) used of \(capacityHuman)"
    }

    public var usageFraction: Double? {
        guard let used = usedBytes, capacityBytes > 0 else { return nil }
        return Double(used) / Double(capacityBytes)
    }

    /// Pretty-print power-on hours: "95 hours", "42 days", "1.2 years".
    public var powerOnHuman: String? {
        guard let h = powerOnHours else { return nil }
        if h < 48 { return "\(h) hours" }
        let days = Double(h) / 24
        if days < 365 { return String(format: "%.0f days", days) }
        return String(format: "%.1f years", days / 365.0)
    }

    /// Pretty-print lifetime host writes: "98 GB" / "12 TB" etc (decimal).
    public var lifetimeWrittenHuman: String? {
        lifetimeWrittenBytes.map { Self.humanBytes($0) }
    }

    public static func humanBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB]
        f.countStyle = .decimal
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: bytes)
    }
}
