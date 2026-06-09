import Foundation

/// Collects facts about a device that smartctl does not report:
/// connection type, dock name, capacity, mount points, filesystem usage.
///
/// All probes shell out to system tools (diskutil, system_profiler) and
/// parse their plist/JSON output — no IOKit linkage required, which keeps
/// the App sandbox-friendly and easy to test.
public actor SystemProbe {

    // Cached Thunderbolt scan, refreshed every 30 s. Walking the TB tree is
    // cheap but adds ~80 ms which we don't want on every menu-bar tick.
    private var cachedThunderboltDocks: [String] = []
    private var thunderboltCachedAt: Date = .distantPast

    public init() {}

    /// Build a `DeviceFacts` for one disk (e.g. `/dev/disk6`) given the
    /// smartctl output we already have. Best-effort; missing fields are nil.
    public func probe(devicePath: String, info: SmartctlInfo) async -> DeviceFacts {
        var facts = DeviceFacts()

        // Brand from PCI vendor ID (NVMe), fallback to model prefix.
        if let vendorID = info.nvme_pci_vendor?.id {
            facts.brand = PCIVendor.name(forID: UInt32(vendorID))
        }
        if facts.brand == nil, let model = info.model_name {
            facts.brand = inferBrand(fromModel: model)
        }

        // Power-on hours from NVMe smart log (or fallback to power_on_time).
        facts.powerOnHours = info.nvme_smart_health_information_log?.power_on_hours
            ?? info.power_on_time?.hours

        // Capacity, bus, mount points from diskutil.
        if let du = diskutilInfo(devicePath: devicePath) {
            facts.capacityBytes = du.size

            switch du.busProtocol {
            case "Apple Fabric":
                facts.bus = .internalNVMe
                facts.connectionLabel = "Apple Fabric (internal)"
            case "PCI-Express":
                // External NVMe — almost certainly Thunderbolt on a Mac
                // (Apple doesn't expose raw PCIe to user-facing ports).
                facts.bus = du.isInternal ? .internalNVMe : .thunderbolt
                facts.connectionLabel = du.isInternal
                    ? "PCI-Express (internal)"
                    : "PCI-Express via Thunderbolt"
            case "USB":
                facts.bus = .usb
                facts.connectionLabel = "USB"
            default:
                facts.bus = .unknown
                facts.connectionLabel = du.busProtocol ?? "Unknown"
            }
        }

        // For Thunderbolt devices, append the first connected dock name.
        if facts.bus == .thunderbolt {
            let docks = await thunderboltDocks()
            if let first = docks.first {
                facts.dockName = first
                facts.connectionLabel = "Thunderbolt · \(first)"
            }
        }

        // Mount points + used bytes (sum across all volumes on this disk).
        let (mounts, used) = mountPointsAndUsage(forWholeDisk: devicePath)
        facts.mountPoints = mounts
        facts.usedBytes = used

        return facts
    }

    // MARK: - diskutil

    private struct DiskutilInfo {
        var size: Int64
        var busProtocol: String?
        var isInternal: Bool
    }

    private func diskutilInfo(devicePath: String) -> DiskutilInfo? {
        guard let plist = runPlist(["/usr/sbin/diskutil", "info", "-plist", devicePath]) else { return nil }
        let size = (plist["TotalSize"] as? NSNumber)?.int64Value ?? (plist["Size"] as? NSNumber)?.int64Value ?? 0
        return DiskutilInfo(
            size: size,
            busProtocol: plist["BusProtocol"] as? String,
            isInternal: (plist["Internal"] as? Bool) ?? false
        )
    }

    private func mountPointsAndUsage(forWholeDisk devicePath: String) -> (mounts: [String], usedBytes: Int64?) {
        guard let listPlist = runPlist(["/usr/sbin/diskutil", "list", "-plist", devicePath]),
              let allDisksAndPartitions = listPlist["AllDisksAndPartitions"] as? [[String: Any]] else {
            return ([], nil)
        }

        // Gather all child volume identifiers (partitions + APFS volumes).
        var childIDs: [String] = []
        for entry in allDisksAndPartitions {
            if let parts = entry["Partitions"] as? [[String: Any]] {
                childIDs.append(contentsOf: parts.compactMap { $0["DeviceIdentifier"] as? String })
            }
            if let apfsVols = entry["APFSVolumes"] as? [[String: Any]] {
                childIDs.append(contentsOf: apfsVols.compactMap { $0["DeviceIdentifier"] as? String })
            }
        }

        var mounts: [String] = []
        var totalUsed: Int64 = 0
        var sawAny = false

        for id in childIDs {
            guard let plist = runPlist(["/usr/sbin/diskutil", "info", "-plist", "/dev/\(id)"]) else { continue }
            guard let mount = plist["MountPoint"] as? String, !mount.isEmpty else { continue }
            mounts.append(mount)
            if let total = (plist["TotalSize"] as? NSNumber)?.int64Value,
               let free  = (plist["FreeSpace"] as? NSNumber)?.int64Value {
                totalUsed += max(0, total - free)
                sawAny = true
            }
        }

        return (mounts, sawAny ? totalUsed : nil)
    }

    // MARK: - Thunderbolt

    private func thunderboltDocks() async -> [String] {
        if Date().timeIntervalSince(thunderboltCachedAt) < 30 {
            return cachedThunderboltDocks
        }
        cachedThunderboltDocks = scanThunderbolt()
        thunderboltCachedAt = Date()
        return cachedThunderboltDocks
    }

    private func scanThunderbolt() -> [String] {
        guard let json = runJSON(["/usr/sbin/system_profiler", "-json", "SPThunderboltDataType"]),
              let buses = (json as? [String: Any])?["SPThunderboltDataType"] as? [[String: Any]]
        else { return [] }

        var names: [String] = []
        func walk(_ node: [String: Any]) {
            // Apple uses "_name" plus a vendor-name-key for connected devices.
            if let kind = node["_name"] as? String,
               !kind.lowercased().contains("bus") {  // skip host bus entries
                names.append(kind)
            }
            // Children appear as nested arrays under various keys.
            for value in node.values {
                if let arr = value as? [[String: Any]] {
                    for child in arr { walk(child) }
                }
            }
        }
        for bus in buses { walk(bus) }
        // De-duplicate while preserving order.
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    // MARK: - process helpers

    private func runPlist(_ argv: [String]) -> [String: Any]? {
        guard let data = run(argv) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private func runJSON(_ argv: [String]) -> Any? {
        guard let data = run(argv) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func run(_ argv: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return out.fileHandleForReading.readDataToEndOfFile()
    }

    // MARK: - small helpers

    private func inferBrand(fromModel model: String) -> String? {
        let lower = model.lowercased()
        let prefixes: [(String, String)] = [
            ("samsung", "Samsung"), ("wd", "Western Digital"), ("wdc", "Western Digital"),
            ("sandisk", "SanDisk"), ("crucial", "Crucial"), ("micron", "Micron"),
            ("sk hynix", "SK hynix"), ("hynix", "SK hynix"),
            ("seagate", "Seagate"), ("kingston", "Kingston"), ("adata", "ADATA"),
            ("lexar", "Lexar"), ("pny", "PNY"), ("apple", "Apple"),
            ("teamgroup", "Team Group"), ("corsair", "Corsair"), ("kioxia", "Kioxia"),
            ("ct", "Crucial"),       // CTxxxx model prefix
        ]
        for (needle, brand) in prefixes where lower.hasPrefix(needle) { return brand }
        return nil
    }
}
