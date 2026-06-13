import Foundation

public struct SmartctlRunner {
    public enum Error: Swift.Error {
        case binaryNotFound
        case executionFailed(Int32, String)
        case decodeFailed(Swift.Error)
        /// The drive's controller rejected the self-test command — typically
        /// a drive that advertises the Self_Test capability bit but doesn't
        /// implement NVMe admin opcode 0x14. Carries smartctl's message.
        case selfTestUnsupported(String)
    }

    public let binaryPath: String

    public init(binaryPath: String? = nil) throws {
        if let p = binaryPath, FileManager.default.isExecutableFile(atPath: p) {
            self.binaryPath = p
            return
        }
        let candidates = [
            "/opt/homebrew/bin/smartctl",
            "/usr/local/bin/smartctl",
            Bundle.main.path(forResource: "smartctl", ofType: nil),
        ].compactMap { $0 }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Error.binaryNotFound
        }
        self.binaryPath = found
    }

    /// Enumerate physical whole-disks via `diskutil list -plist` and return
    /// them as `/dev/diskN` device paths.
    ///
    /// We deliberately do NOT use `smartctl --scan` on macOS: it returns
    /// IOService paths (e.g. `IOService:/AppleARMPE/.../NS_01@1`) rather
    /// than BSD device paths. Those work for smartctl itself but break any
    /// downstream consumer that wants to call `diskutil` or `statfs` with
    /// the same identifier.
    public func scan() throws -> [ScannedDevice] {
        let plist = try diskutilListPlist()
        guard let entries = plist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let id = entry["DeviceIdentifier"] as? String else { return nil }
            // Fast path: synthesized APFS containers carry this key. Skip
            // without spawning a subprocess — these are not real hardware.
            if entry["APFSPhysicalStores"] != nil { return nil }
            // Remaining candidates may still be disk images (sparsebundles,
            // simulator volumes). One diskutil info call confirms.
            if isVirtual(deviceIdentifier: id) { return nil }
            return ScannedDevice(name: "/dev/\(id)", type: "auto", protocol_: nil)
        }
    }

    private func diskutilListPlist() throws -> [String: Any] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["list", "-plist"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (try PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }

    private func isVirtual(deviceIdentifier id: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["info", "-plist", "/dev/\(id)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        if let kind = plist?["VirtualOrPhysical"] as? String, kind == "Virtual" { return true }
        if let proto = plist?["BusProtocol"] as? String, proto == "Disk Image" { return true }
        return false
    }

    public func info(device: String, extraArgs: [String] = []) throws -> SmartctlInfo {
        let data = try run(["--json=c", "-a"] + extraArgs + [device])
        return try decode(SmartctlInfo.self, from: data)
    }

    /// Kick off a SMART/NVMe **extended** ("long") device self-test. This is
    /// a foreground command that returns once the drive has accepted the
    /// request — the test then runs on the drive itself, surviving sleep and
    /// app restarts. Poll `info(device:)` and read `selfTest` for progress.
    ///
    /// Throws `.selfTestUnsupported` when the controller rejects the command.
    /// `run()` can't catch this on its own: smartctl prints the rejection to
    /// stdout (so the data is non-empty) yet sets a non-zero exit bitmask, so
    /// we inspect the status + message here.
    public func startExtendedSelfTest(device: String, extraArgs: [String] = []) throws {
        let (status, output) = try runRaw(extraArgs + ["-t", "long", device])
        let lower = output.lowercased()
        // Exit bit 2 (0x04) = "a SMART/ATA command to the disk failed".
        if (status & 0b100) != 0 || lower.contains("not supported") || lower.contains("invalid") {
            throw Error.selfTestUnsupported(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Run smartctl and return its raw exit status plus combined
    /// stdout+stderr. Unlike `run`, never throws on a non-zero status — the
    /// caller interprets smartctl's exit bitmask itself.
    public func runRaw(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out + err)
    }

    /// Abort an in-progress self-test (`smartctl -X`).
    public func abortSelfTest(device: String, extraArgs: [String] = []) throws {
        _ = try run(extraArgs + ["-X", device])
    }

    @discardableResult
    public func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        // smartctl uses bitmask exit codes; bit 0/1/2 indicate command failure.
        let fatal: Int32 = 0b111
        if (process.terminationStatus & fatal) != 0 && data.isEmpty {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Error.executionFailed(process.terminationStatus, err)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw Error.decodeFailed(error) }
    }
}

public struct ScannedDevice: Decodable, Sendable {
    public let name: String
    public let type: String
    public let protocol_: String?
    enum CodingKeys: String, CodingKey { case name, type, protocol_ = "protocol" }
}

public struct SmartctlScan: Decodable {
    public let devices: [ScannedDevice]
}

public struct SmartctlInfo: Decodable, Sendable {
    public let device: DeviceInfo
    public let model_name: String?
    public let serial_number: String?
    public let firmware_version: String?
    public let user_capacity: Capacity?
    public let temperature: TempInfo?
    public let nvme_smart_health_information_log: NVMeHealth?
    public let nvme_pci_vendor: PCIVendorInfo?
    public let smart_status: SmartStatus?
    public let power_on_time: PowerOn?
    public let power_cycle_count: Int?
    // Self-test status + log. ATA and NVMe report these in different
    // subtrees; both are optional and `selfTest` (see SelfTest.swift)
    // normalizes whichever is present.
    public let ata_smart_data: ATASmartData?
    public let ata_smart_self_test_log: ATASelfTestLog?
    public let nvme_self_test_log: NVMeSelfTestLog?

    /// A `{ value, string }` pair — smartctl's standard shape for an
    /// enumerated field with a human label.
    public struct ValueString: Decodable, Sendable {
        public let value: Int?
        public let string: String?
    }

    public struct ATASmartData: Decodable, Sendable {
        public let self_test: SelfTest?
        public struct SelfTest: Decodable, Sendable {
            public let status: Status?
            public let polling_minutes: PollingMinutes?
            public struct Status: Decodable, Sendable {
                public let value: Int?
                public let string: String?
                public let remaining_percent: Int?
                public let passed: Bool?
            }
            public struct PollingMinutes: Decodable, Sendable {
                public let short: Int?
                public let extended: Int?
            }
        }
    }

    public struct ATASelfTestLog: Decodable, Sendable {
        public let standard: Standard?
        public struct Standard: Decodable, Sendable {
            public let table: [Entry]?
            public struct Entry: Decodable, Sendable {
                public let type: ValueString?
                public let status: Status?
                public let lifetime_hours: Int?
                public struct Status: Decodable, Sendable {
                    public let value: Int?
                    public let string: String?
                    public let passed: Bool?
                }
            }
        }
    }

    public struct NVMeSelfTestLog: Decodable, Sendable {
        public let current_self_test_operation: ValueString?
        public let current_self_test_completion_percent: Int?
        public let table: [Entry]?
        public struct Entry: Decodable, Sendable {
            public let self_test_code: ValueString?
            public let self_test_result: ValueString?
            public let power_on_hours: Int?
        }
    }

    public struct PCIVendorInfo: Decodable, Sendable {
        public let id: Int?
        public let subsystem_id: Int?
    }

    public struct DeviceInfo: Decodable, Sendable {
        public let name: String
        public let type: String
        public let protocol_: String?
        enum CodingKeys: String, CodingKey { case name, type, protocol_ = "protocol" }
    }
    public struct Capacity: Decodable, Sendable { public let bytes: Int64? }
    public struct TempInfo: Decodable, Sendable { public let current: Int? }
    public struct SmartStatus: Decodable, Sendable { public let passed: Bool? }
    public struct PowerOn: Decodable, Sendable { public let hours: Int? }
    public struct NVMeHealth: Decodable, Sendable {
        public let temperature: Int?
        public let available_spare: Int?
        public let available_spare_threshold: Int?
        public let percentage_used: Int?
        public let data_units_read: Int64?
        public let data_units_written: Int64?
        public let host_reads: Int64?
        public let host_writes: Int64?
        public let controller_busy_time: Int64?
        public let power_cycles: Int?
        public let power_on_hours: Int?
        public let unsafe_shutdowns: Int?
        public let media_errors: Int?
        public let num_err_log_entries: Int64?
        public let warning_temp_time: Int?
        public let critical_comp_time: Int?
        public let temperature_sensors: [Int]?
    }
}
