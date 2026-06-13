import Foundation

public extension SmartctlInfo {
    /// True when smartctl actually got SMART data back — not just a clean
    /// JSON envelope describing the device with no health payload. Used to
    /// reject `-d` candidates that "open" the device but can't read SMART.
    var hasUsableSmart: Bool {
        smart_status?.passed != nil
            || nvme_smart_health_information_log != nil
            || temperature?.current != nil
    }
}

/// Active `-d` probing for USB bridges macOS won't auto-translate.
///
/// Many USB-SATA / USB-NVMe enclosures *can* pass SMART through on macOS,
/// but only when smartctl is told the exact translation layer to use
/// (`-d sat,16`, `-d usbjmicron`, …). The default open doesn't try these,
/// so the drive looks "blocked." This walks the standard ladder and returns
/// the first device-type that yields a real SMART read — unlocking coverage
/// with zero kernel extension. Bridges macOS filters at the SCSI layer
/// (the truly-blocked ones) simply fail every rung, which the caller caches
/// so the ~dozen subprocess spawns happen once, not every poll.
public enum SmartctlProbe {
    /// Ordered by how commonly each unlocks a real-world enclosure. `sat`
    /// variants cover most SATA bridges; the `usb*` and `snt*` types cover
    /// vendor-specific SATA and NVMe bridges respectively.
    public static let typeLadder: [[String]] = [
        ["-d", "sat"],
        ["-d", "sat,16"],
        ["-d", "sat,12"],
        ["-d", "usbjmicron"],
        ["-d", "usbsunplus"],
        ["-d", "usbcypress"],
        ["-d", "usbprolific"],
        ["-d", "sntasmedia"],
        ["-d", "sntjmicron"],
        ["-d", "sntrealtek"],
    ]

    /// Try each candidate in order; return the first whose probe yields a
    /// usable SMART read. `probe` is injected so this is unit-testable
    /// without spawning smartctl.
    public static func firstWorking(
        candidates: [[String]] = typeLadder,
        probe: ([String]) -> SmartctlInfo?
    ) -> (args: [String], info: SmartctlInfo)? {
        for args in candidates {
            if let info = probe(args), info.hasUsableSmart {
                return (args, info)
            }
        }
        return nil
    }
}
