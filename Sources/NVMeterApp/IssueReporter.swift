import Foundation
import AppKit
import NVMeterCore

/// Builds a "this enclosure couldn't read SMART, please add it to the
/// database" GitHub Issue from a single click in the popover.
///
/// Goal: turn every blocked-device card into a potential drivedb PR.
/// We collect ioreg + smartctl + diskutil output for the device, format
/// it as Markdown, and open a pre-filled GitHub New Issue page in the
/// user's browser. If the payload exceeds the safe URL length we fall
/// back to copying the body to the clipboard and opening the issue page
/// with just a hint.
@MainActor
enum IssueReporter {

    /// Max URL length we'll attempt to embed in a single click. GitHub
    /// technically accepts ~8 KB but Safari truncates around this size.
    private static let maxURLBytes = 6000

    private static let drivedbRepo = "hualiu77/NVMeter-drivedb"

    /// Build the report and open it in the browser. Safe to call from
    /// the main thread; the diagnostic gathering runs off-actor.
    static func report(for snapshot: DeviceSnapshot) {
        // Snapshot the few fields the detached work needs so we don't
        // capture the @MainActor-bound struct across an isolation hop.
        let modelName    = snapshot.modelName
        let devicePath   = snapshot.devicePath
        let connection   = snapshot.facts.connectionLabel
        let capacity     = snapshot.facts.capacityBytes
        let mountPoints  = snapshot.facts.mountPoints
        let version      = nvmeterVersion()

        Task.detached {
            let title = composeTitle(model: modelName, connection: connection)
            let body  = composeBody(
                model: modelName,
                devicePath: devicePath,
                connection: connection,
                capacity: capacity,
                mountPoints: mountPoints,
                version: version
            )
            await MainActor.run { openOrCopy(title: title, body: body) }
        }
    }

    // MARK: - Composition (nonisolated — safe off-actor)

    nonisolated private static func composeTitle(model: String, connection: String) -> String {
        "Enclosure report: \(model) (\(connection))"
    }

    nonisolated private static func composeBody(
        model: String,
        devicePath: String,
        connection: String,
        capacity: Int64,
        mountPoints: [String],
        version: String
    ) -> String {
        let env = environmentBlock(version: version)
        let device = deviceBlock(model: model, devicePath: devicePath,
                                 connection: connection, capacity: capacity,
                                 mountPoints: mountPoints)
        let ioregBlock = ioregForBSD(devicePath)
        let smartctlBlock = smartctlProbes(for: devicePath)
        let diskutilBlock = diskutilInfo(for: devicePath)

        return """
        ## What I'm reporting

        NVMeter could not read SMART on this enclosure on my Mac. The detected
        bridge appears to be `\(model)` over `\(connection)`.

        **Fill in if you know:**
        - Enclosure brand + model (e.g. "Orico M2PVC3-G20"):
        - Drive inside (e.g. "Crucial P3 Plus 1 TB"):
        - Anything special about the connection (cable, hub, dock):

        ## Environment

        \(env)

        ## Device

        \(device)

        ## diskutil info

        ```
        \(diskutilBlock)
        ```

        ## ioreg (USB-side ancestry of the disk)

        ```
        \(ioregBlock)
        ```

        ## smartctl probes

        Every standard `-d` variant that NVMeter tries:

        ```
        \(smartctlBlock)
        ```

        ---

        _Submitted from NVMeter \(version) — a single click on the
        "Help map this enclosure" button generated this report._
        """
    }

    // MARK: - Open / copy fallback

    private static func openOrCopy(title: String, body: String) {
        let url = newIssueURL(title: title, body: body)
        let safe = url.absoluteString.lengthOfBytes(using: .utf8) <= maxURLBytes

        if safe {
            NSWorkspace.shared.open(url)
            return
        }

        // Body too big to fit in the URL — copy to clipboard, open an
        // empty issue page, and notify the user to paste.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(body, forType: .string)

        let shortURL = newIssueURL(
            title: title,
            body: "_NVMeter's diagnostic report was too large for a URL; it's already on your clipboard. **Press ⌘V here.**_"
        )
        NSWorkspace.shared.open(shortURL)

        let alert = NSAlert()
        alert.messageText = "Report copied to clipboard"
        alert.informativeText = "The full report didn't fit in a URL, so NVMeter copied it instead. Paste (⌘V) into the GitHub issue that just opened, then submit."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func newIssueURL(title: String, body: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "github.com"
        c.path = "/\(drivedbRepo)/issues/new"
        c.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "bridge-data,from-app"),
        ]
        return c.url!
    }

    // MARK: - Diagnostic gathering (all nonisolated)

    nonisolated private static func environmentBlock(version: String) -> String {
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        let model = sysctlString("hw.model") ?? "unknown"
        let cpu   = sysctlString("machdep.cpu.brand_string") ?? "unknown"
        return """
        - NVMeter \(version)
        - macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)
        - Hardware: \(model)
        - CPU: \(cpu)
        """
    }

    nonisolated private static func deviceBlock(
        model: String,
        devicePath: String,
        connection: String,
        capacity: Int64,
        mountPoints: [String]
    ) -> String {
        let capStr = ByteCountFormatter.string(fromByteCount: capacity, countStyle: .decimal)
        let mounts = mountPoints.joined(separator: ", ")
        return """
        - BSD path: `\(devicePath)`
        - NVMeter saw model: `\(model)`
        - Connection: \(connection)
        - Capacity: \(capStr)
        - Mount point(s): \(mounts.isEmpty ? "(none)" : mounts)
        """
    }

    nonisolated private static func ioregForBSD(_ bsd: String) -> String {
        // Dump every USB device the host knows about, one compact record
        // each. The maintainer (or the user) can identify which one
        // corresponds to this enclosure from the product / vendor names.
        // We deliberately do NOT try to graph-walk from the IOMedia node
        // up to the USB device: the ancestry trees are huge and the
        // user-readable identifying info lives in this flat list anyway.
        let raw = run("/usr/sbin/ioreg",
                      ["-r", "-c", "IOUSBHostDevice", "-d", "1", "-w", "0"])
        let interesting = #"^\s+"(USB Vendor Name|USB Product Name|idVendor|idProduct|USB Serial Number|UsbLinkSpeed|USBSpeed|bcdDevice)"\s*="#
        let regex = try? NSRegularExpression(pattern: interesting)

        // Split into per-device blocks at each `+-o ` header.
        var records: [[String]] = [[]]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.contains("+-o ") && s.contains("class IOUSBHostDevice") {
                records.append([s.trimmingCharacters(in: .whitespaces)])
            } else if let regex {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if regex.firstMatch(in: s, range: range) != nil {
                    records[records.count - 1].append(s.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        // Drop empty leading record and any device that doesn't have a
        // product name (root hubs, billboard devices, etc.).
        let formatted = records
            .filter { block in block.contains(where: { $0.contains("USB Product Name") }) }
            .map { $0.joined(separator: "\n") }

        // Note which BSD the report is about so the maintainer can match
        // it to the right device by USB ID lookup.
        let header = "[NVMeter is reporting from BSD device: \(bsd)]\n\n"
        return header + formatted.joined(separator: "\n\n").prefix(4000)
    }

    nonisolated private static func smartctlProbes(for bsd: String) -> String {
        let flagSets: [[String]] = [
            [],
            ["-d", "sat"],
            ["-d", "sat,12"],
            ["-d", "sat,16"],
            ["-d", "sat,auto"],
            ["-d", "usbjmicron"],
            ["-d", "usbsunplus"],
            ["-d", "usbcypress"],
            ["-d", "usbprolific"],
            ["-d", "sntasmedia"],
            ["-d", "sntjmicron"],
            ["-d", "sntrealtek"],
            ["-d", "nvme"],
        ]
        var transcript: [String] = []
        let binary = findSmartctl() ?? "/opt/homebrew/bin/smartctl"
        for flags in flagSets {
            let argv = flags + ["-i", bsd]
            let out = run(binary, argv)
                .split(separator: "\n").prefix(5).joined(separator: "\n")
            let cmd = ([binary.split(separator: "/").last.map(String.init) ?? "smartctl"] + argv).joined(separator: " ")
            transcript.append("$ \(cmd)\n\(out)")
        }
        return transcript.joined(separator: "\n\n")
    }

    nonisolated private static func diskutilInfo(for bsd: String) -> String {
        run("/usr/sbin/diskutil", ["info", bsd])
            .split(separator: "\n")
            .filter { line in
                // Drop UUIDs / volume-internal noise we don't need.
                let s = String(line)
                return !s.contains("UUID")
                    && !s.contains("Owner")
                    && !s.isEmpty
            }
            .joined(separator: "\n")
    }

    // MARK: - Helpers (nonisolated)

    nonisolated private static func mediaName(for bsd: String) -> String? {
        // diskutil info gives us MediaName which matches the IOReg node.
        let out = run("/usr/sbin/diskutil", ["info", "-plist", bsd])
        guard let data = out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["MediaName"] as? String
    }

    nonisolated private static func nvmeterVersion() -> String {
        let dict = Bundle.main.infoDictionary
        let version = dict?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = dict?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (build \(build))"
    }

    nonisolated private static func findSmartctl() -> String? {
        if let bundled = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("smartctl").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        for candidate in ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    nonisolated private static func run(_ executable: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out
        p.standardError  = err
        do { try p.run() } catch { return "(failed to run \(executable))" }
        p.waitUntilExit()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let combined = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
