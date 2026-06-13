import Foundation

/// Result of polling one device.
public enum DeviceReport: Sendable {
    /// smartctl read succeeded → full health data + system facts.
    case healthy(info: SmartctlInfo, assessment: HealthAssessment, facts: DeviceFacts)

    /// smartctl couldn't open the device (typical for USB-SATA / USB-NVMe
    /// bridges on macOS). We still surface the device in the UI with the
    /// non-SMART facts we *can* probe (capacity, mount, connection, brand).
    case blocked(devicePath: String, facts: DeviceFacts)

    public var devicePath: String {
        switch self {
        case .healthy(let info, _, _): info.device.name
        case .blocked(let path, _): path
        }
    }

    public var facts: DeviceFacts {
        switch self {
        case .healthy(_, _, let f): f
        case .blocked(_, let f): f
        }
    }
}

public actor MonitoringService {
    private let runner: SmartctlRunner
    private let scorer = HealthScorer()
    private let probe = SystemProbe()
    private let store: HistoryStore
    private let interval: TimeInterval
    private let bridgeDB: BridgeDatabase
    /// Remembered per-device working args so retries cost one process
    /// spawn instead of a probe loop on every tick.
    private var workingArgsByDevice: [String: [String]] = [:]
    /// Device paths whose full `-d` probe ladder came up empty, so we don't
    /// re-spawn a dozen subprocesses every poll for a truly-blocked drive.
    /// Pruned each tick to currently-attached devices, so re-plugging gets
    /// a fresh probe.
    private var probeLadderFailed: Set<String> = []

    public init(
        runner: SmartctlRunner,
        store: HistoryStore,
        interval: TimeInterval = 300,
        bridgeDB: BridgeDatabase = .loadDefault()
    ) {
        self.runner = runner
        self.store = store
        self.interval = interval
        self.bridgeDB = bridgeDB
    }

    /// Recent samples for one device, newest first.
    public func history(devicePath: String, limit: Int = 2000) throws -> [HealthSample] {
        try store.recent(device: devicePath, limit: limit)
    }

    public func tickOnce() async throws -> [DeviceReport] {
        let scanned = try runner.scan()
        // Snapshot the USB device list once per tick — it's the same for
        // every disk and ioreg costs ~50 ms.
        let usbDevices = USBDeviceCatalog.enumerate()

        var results: [DeviceReport] = []
        for d in scanned {
            var info = try? runner.info(device: d.name)
            var matchedEntry: BridgeEntry?
            var workingArgs: [String]?
            var discoveredByProbe = false

            // Default open failed → try the community bridge database.
            if info == nil {
                (info, matchedEntry, workingArgs) = retryViaBridgeDB(
                    devicePath: d.name, usbDevices: usbDevices
                )
            } else if let cached = workingArgsByDevice[d.name] {
                workingArgs = cached
            }

            // Still blocked and not catalogued → walk the `-d` ladder once.
            // This unlocks cooperative bridges macOS doesn't auto-translate,
            // without any kext. Negative results are cached for the device's
            // lifetime so we don't re-probe every poll.
            if info == nil, matchedEntry == nil, !probeLadderFailed.contains(d.name) {
                if let hit = SmartctlProbe.firstWorking(probe: { try? runner.info(device: d.name, extraArgs: $0) }) {
                    info = hit.info
                    workingArgs = hit.args
                    workingArgsByDevice[d.name] = hit.args
                    discoveredByProbe = true
                } else {
                    probeLadderFailed.insert(d.name)
                }
            }

            var facts = await probe.probe(devicePath: d.name, info: info)
            facts.argsDiscoveredByProbe = discoveredByProbe
            // Even when retry fails, knowing the bridge is in the DB is
            // valuable UI state ("already catalogued, macOS-blocked").
            if matchedEntry == nil, info == nil,
               let media = facts.modelHint,
               let usb = USBDeviceCatalog.match(mediaName: media, in: usbDevices) {
                matchedEntry = bridgeDB.lookup(usbID: usb.usbID)
            }
            facts.knownBridgeName = matchedEntry?.bridge
            facts.workingSmartctlArgs = workingArgs

            if let info {
                let assessment = scorer.assess(info)
                let sample = HealthSample(
                    id: nil,
                    deviceName: info.device.name,
                    serial: info.serial_number,
                    timestamp: Date(),
                    temperatureC: info.temperature?.current ?? info.nvme_smart_health_information_log?.temperature,
                    percentageUsed: info.nvme_smart_health_information_log?.percentage_used,
                    availableSpare: info.nvme_smart_health_information_log?.available_spare,
                    mediaErrors: info.nvme_smart_health_information_log?.media_errors,
                    dataUnitsWritten: info.nvme_smart_health_information_log?.data_units_written,
                    healthLevel: assessment.level.rawValue
                )
                try? store.insert(sample)
                results.append(.healthy(info: info, assessment: assessment, facts: facts))
            } else {
                // Don't surface system-level virtual drives that just happened
                // to slip past the scan filter. We require at least a capacity
                // OR a non-empty media hint to call something a "real" disk.
                if facts.capacityBytes > 0 || facts.modelHint != nil {
                    results.append(.blocked(devicePath: d.name, facts: facts))
                }
            }
        }
        try? store.prune()
        // Forget probe failures for devices no longer attached, so a
        // re-plugged (possibly different) enclosure at the same path is
        // probed fresh rather than assumed blocked.
        probeLadderFailed.formIntersection(Set(scanned.map(\.name)))
        return results
    }

    /// Map the disk's MediaName to an attached USB device, look up its
    /// USB ID in the bridge database, and re-run smartctl with the entry's
    /// `-d` flags. Caches the working args per device path.
    private func retryViaBridgeDB(
        devicePath: String,
        usbDevices: [USBDevice]
    ) -> (SmartctlInfo?, BridgeEntry?, [String]?) {
        // Cheapest first: previously-discovered working args.
        if let cached = workingArgsByDevice[devicePath],
           let info = try? runner.info(device: devicePath, extraArgs: cached) {
            return (info, nil, cached)
        }

        guard let mediaName = mediaName(for: devicePath),
              let usb = USBDeviceCatalog.match(mediaName: mediaName, in: usbDevices),
              let entry = bridgeDB.lookup(usbID: usb.usbID)
        else { return (nil, nil, nil) }

        guard !entry.smartctl_args.isEmpty else {
            // Catalogued as known-blocked (e.g. WD Elements on macOS).
            return (nil, entry, nil)
        }

        if let info = try? runner.info(device: devicePath, extraArgs: entry.smartctl_args) {
            workingArgsByDevice[devicePath] = entry.smartctl_args
            return (info, entry, entry.smartctl_args)
        }
        // Entry exists but the flags don't work on macOS — still report
        // the match so the UI can say "known bridge, blocked by macOS".
        return (nil, entry, nil)
    }

    private func mediaName(for devicePath: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["info", "-plist", devicePath]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        return plist?["MediaName"] as? String
    }
}
