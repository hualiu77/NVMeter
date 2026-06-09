import Foundation

public struct SmartctlRunner {
    public enum Error: Swift.Error {
        case binaryNotFound
        case executionFailed(Int32, String)
        case decodeFailed(Swift.Error)
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
        public let power_cycles: Int?
        public let power_on_hours: Int?
        public let unsafe_shutdowns: Int?
        public let media_errors: Int?
        public let warning_temp_time: Int?
        public let critical_comp_time: Int?
    }
}
