import Foundation

/// Collects facts about a device that smartctl does not report:
/// connection type, dock name, capacity, mount points, filesystem usage.
///
/// All probes shell out to system tools (diskutil, system_profiler) and
/// parse their plist/JSON output — no IOKit linkage required, which keeps
/// the App sandbox-friendly and easy to test.
public actor SystemProbe {

    private var cachedThunderboltDocks: [String] = []
    private var thunderboltCachedAt: Date = .distantPast

    private var cachedDiskMap: [String: DiskMountSummary] = [:]
    private var diskMapCachedAt: Date = .distantPast

    public init() {}

    /// Probe a device. `info` is nil for devices smartctl couldn't read
    /// (most USB-SATA bridges on macOS) — in that case we fill `modelHint`
    /// and `brand` from `diskutil info`'s MediaName as a graceful fallback.
    public func probe(devicePath: String, info: SmartctlInfo?) async -> DeviceFacts {
        var facts = DeviceFacts()

        if let info {
            if let vendorID = info.nvme_pci_vendor?.id {
                facts.brand = PCIVendor.name(forID: UInt32(vendorID))
            }
            if facts.brand == nil, let model = info.model_name {
                facts.brand = inferBrand(fromModel: model)
            }
            facts.powerOnHours = info.nvme_smart_health_information_log?.power_on_hours
                ?? info.power_on_time?.hours
        }

        if let du = diskutilInfo(devicePath: devicePath) {
            facts.capacityBytes = du.size
            facts.modelHint = du.mediaName
            if facts.brand == nil, let media = du.mediaName {
                facts.brand = inferBrand(fromModel: media)
            }

            switch du.busProtocol {
            case "Apple Fabric":
                facts.bus = .internalNVMe
                facts.connectionLabel = "Apple Fabric (internal)"
            case "PCI-Express":
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

        if facts.bus == .thunderbolt {
            let docks = await thunderboltDocks()
            if let first = docks.first {
                facts.dockName = first
                facts.connectionLabel = "Thunderbolt · \(first)"
            }
        }

        // Mount points + used bytes, computed from a parsed global disk map.
        let id = devicePath.replacingOccurrences(of: "/dev/", with: "")
        if let summary = diskMap()[id] {
            facts.mountPoints = summary.mountPoints
            facts.usedBytes = summary.usedBytes
        }

        return facts
    }

    // MARK: - diskutil info (per-device)

    private struct DiskutilInfo {
        var size: Int64
        var busProtocol: String?
        var isInternal: Bool
        var mediaName: String?
    }

    private func diskutilInfo(devicePath: String) -> DiskutilInfo? {
        guard let plist = runPlist(["/usr/sbin/diskutil", "info", "-plist", devicePath]) else { return nil }
        let size = (plist["TotalSize"] as? NSNumber)?.int64Value ?? (plist["Size"] as? NSNumber)?.int64Value ?? 0
        return DiskutilInfo(
            size: size,
            busProtocol: plist["BusProtocol"] as? String,
            isInternal: (plist["Internal"] as? Bool) ?? false,
            mediaName: plist["MediaName"] as? String
        )
    }

    // MARK: - global disk map (cached)

    private struct DiskMountSummary {
        var mountPoints: [String]
        var usedBytes: Int64
    }

    /// Returns a cached `wholeDiskID → mounted volumes` map.
    /// Handles APFS synthesized containers: a volume mounted from `disk7s1`
    /// whose container `disk7` is backed by `disk6s2` is correctly counted
    /// against the *physical* whole disk `disk6`.
    private func diskMap() -> [String: DiskMountSummary] {
        if Date().timeIntervalSince(diskMapCachedAt) < 5 { return cachedDiskMap }

        var map: [String: DiskMountSummary] = [:]
        guard let plist = runPlist(["/usr/sbin/diskutil", "list", "-plist"]),
              let entries = plist["AllDisksAndPartitions"] as? [[String: Any]]
        else {
            cachedDiskMap = map
            diskMapCachedAt = Date()
            return map
        }

        // Pass 1: synthesized-container → physical whole-disk mapping.
        // Entry of `disk7` carries `APFSPhysicalStores` with `DeviceIdentifier = "disk6s2"`.
        // `disk6s2` → `disk6` after stripping the partition suffix.
        var synthToPhysical: [String: String] = [:]
        for entry in entries {
            guard let id = entry["DeviceIdentifier"] as? String,
                  let stores = entry["APFSPhysicalStores"] as? [[String: Any]],
                  let firstStoreDev = stores.first?["DeviceIdentifier"] as? String
            else { continue }
            synthToPhysical[id] = stripPartition(firstStoreDev)
        }

        // Pass 2: walk every volume / mounted partition and tally against
        // the physical disk it lives on.
        //
        // CAREFUL on APFS containers: every volume inside a container
        // shares the same physical pool, and `statfs` on any of them
        // reports the SAME container-level used bytes. Summing them would
        // 5×-count the same data (e.g. Apple boot SSD would report 2 TB
        // used of a 500 GB disk). So for each container we take the
        // first mounted volume's usage exactly once and list all the
        // mount points for display purposes.
        for entry in entries {
            guard let id = entry["DeviceIdentifier"] as? String else { continue }
            let realDisk = synthToPhysical[id] ?? id

            // Plain (non-APFS) partitions: each is its own physical region.
            for part in (entry["Partitions"] as? [[String: Any]] ?? []) {
                accumulatePartition(part, into: &map, key: realDisk)
            }

            // APFS container: collect all mounts, but charge usage only once.
            let mountedAPFSVolumes: [String] = (entry["APFSVolumes"] as? [[String: Any]] ?? [])
                .compactMap { ($0["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if let representative = mountedAPFSVolumes.first,
               let containerUsed = statfsUsage(at: representative) {
                var existing = map[realDisk] ?? DiskMountSummary(mountPoints: [], usedBytes: 0)
                existing.mountPoints.append(contentsOf: mountedAPFSVolumes)
                existing.usedBytes += containerUsed
                map[realDisk] = existing
            }
        }

        cachedDiskMap = map
        diskMapCachedAt = Date()
        return map
    }

    /// Accumulate one non-APFS partition (independent physical region).
    private func accumulatePartition(
        _ partition: [String: Any],
        into map: inout [String: DiskMountSummary],
        key: String
    ) {
        guard let mount = partition["MountPoint"] as? String, !mount.isEmpty else { return }
        guard let usage = statfsUsage(at: mount) else { return }
        var existing = map[key] ?? DiskMountSummary(mountPoints: [], usedBytes: 0)
        existing.mountPoints.append(mount)
        existing.usedBytes += usage
        map[key] = existing
    }

    /// Returns USED bytes (total − free) for a mounted filesystem.
    /// Uses Foundation's `FileManager.attributesOfFileSystem(forPath:)`
    /// which wraps `statvfs(3)` and gives more accurate numbers than
    /// diskutil's `FreeSpace`, which can be 0 just after a remount.
    private func statfsUsage(at path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = (attrs[.systemSize] as? NSNumber)?.int64Value,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
        else { return nil }
        return max(0, total - free)
    }

    /// "disk0s2" → "disk0";  "disk14s3" → "disk14";  "disk6" → "disk6".
    ///
    /// We can't just `firstIndex(of: "s")` because the literal "disk" itself
    /// contains an 's' (the one in "di**s**k"), which would slice the wrong
    /// place and silently break the synthesized-container → physical-disk
    /// mapping. Walk the prefix explicitly: consume "disk" then digits.
    private func stripPartition(_ deviceID: String) -> String {
        guard deviceID.hasPrefix("disk") else { return deviceID }
        var endIdx = deviceID.index(deviceID.startIndex, offsetBy: 4)
        while endIdx < deviceID.endIndex, deviceID[endIdx].isNumber {
            endIdx = deviceID.index(after: endIdx)
        }
        return String(deviceID[..<endIdx])
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
            if let kind = node["_name"] as? String,
               !kind.lowercased().contains("bus") {
                let vendor = (node["vendor_name_key"] as? String) ?? ""
                names.append(vendor.isEmpty ? kind : "\(vendor) \(kind)")
            }
            for value in node.values {
                if let arr = value as? [[String: Any]] {
                    for child in arr { walk(child) }
                }
            }
        }
        for bus in buses { walk(bus) }
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

    private func inferBrand(fromModel model: String) -> String? {
        let lower = model.lowercased()
        let prefixes: [(String, String)] = [
            ("samsung", "Samsung"), ("wd", "Western Digital"), ("wdc", "Western Digital"),
            ("sandisk", "SanDisk"), ("crucial", "Crucial"), ("micron", "Micron"),
            ("sk hynix", "SK hynix"), ("hynix", "SK hynix"),
            ("seagate", "Seagate"), ("kingston", "Kingston"), ("adata", "ADATA"),
            ("lexar", "Lexar"), ("pny", "PNY"), ("apple", "Apple"),
            ("teamgroup", "Team Group"), ("corsair", "Corsair"), ("kioxia", "Kioxia"),
            ("ct", "Crucial"),
        ]
        for (needle, brand) in prefixes where lower.hasPrefix(needle) { return brand }
        return nil
    }
}
