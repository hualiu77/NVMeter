import Foundation

/// Resolves the *official* warranty-check page for a drive's brand. NVMeter
/// never sends the serial anywhere itself — it opens the manufacturer's own
/// page in the user's browser (a transparent, user-initiated request) and
/// copies the serial to the clipboard so it's one paste away. This keeps the
/// "no telemetry, no cloud" promise intact while still getting the user to
/// the right place.
public enum WarrantyLinks {
    /// Which serial the destination checker actually wants pasted in.
    public enum SerialSource: Sendable, Equatable {
        case driveSerial     // the drive's own serial (Seagate, WD)
        case machineSerial   // the host Mac's serial (Apple coverage check)
        case none            // policy page only, nothing to paste
    }

    public struct Target: Sendable, Equatable {
        public let url: URL
        /// True when `url` is a brand-official page; false when we fell back
        /// to a web search (brand not in our map).
        public let isOfficial: Bool
        /// What the destination page checks by. `.none` means it's only a
        /// warranty *policy* page — Crucial, Samsung, Kingston, etc. don't
        /// offer an online serial checker; their warranty simply runs N years
        /// from purchase.
        public let serial: SerialSource
        public let brandLabel: String

        /// Convenience: does the destination let you look coverage up at all?
        public var hasSerialLookup: Bool { serial != .none }
    }

    /// Official warranty / support pages for the major brands. No serial ever
    /// goes in the query string — these are plain page URLs.
    private static let official: [(needle: String, label: String, url: String, serial: SerialSource)] = [
        // Apple's coverage check is keyed by the *Mac's* serial, not the SSD's.
        ("apple",           "Apple",            "https://checkcoverage.apple.com/", .machineSerial),
        ("western digital", "Western Digital",  "https://support.wdc.com/warranty/warrantystatus.aspx", .driveSerial),
        ("wd",              "Western Digital",  "https://support.wdc.com/warranty/warrantystatus.aspx", .driveSerial),
        ("sandisk",         "SanDisk",          "https://support.wdc.com/warranty/warrantystatus.aspx", .driveSerial),
        ("seagate",         "Seagate",          "https://www.seagate.com/support/warranty-and-replacements/", .driveSerial),
        ("samsung",         "Samsung",          "https://semiconductor.samsung.com/consumer-storage/support/warranty/", .none),
        ("crucial",         "Crucial",          "https://www.crucial.com/support/warranty", .none),
        ("micron",          "Crucial",          "https://www.crucial.com/support/warranty", .none),
        ("kingston",        "Kingston",         "https://www.kingston.com/en/support", .none),
        ("sk hynix",        "SK hynix",         "https://ssd.skhynix.com/support/", .none),
        ("skhynix",         "SK hynix",         "https://ssd.skhynix.com/support/", .none),
        ("kioxia",          "KIOXIA",           "https://personal.kioxia.com/en-us/support/warranty.html", .none),
        ("adata",           "ADATA",            "https://www.adata.com/en/support/online/", .none),
    ]

    /// Resolve a warranty target from the brand and/or model strings.
    public static func target(brand: String?, model: String) -> Target {
        let hay = ((brand ?? "") + " " + model).lowercased()
        for entry in official where hay.contains(entry.needle) {
            return Target(url: URL(string: entry.url)!, isOfficial: true,
                          serial: entry.serial, brandLabel: entry.label)
        }
        // Unknown brand → a plain web search for its warranty checker. No
        // serial included.
        let brandTerm = (brand ?? model.split(separator: " ").first.map(String.init) ?? "SSD")
        let q = "\(brandTerm) SSD warranty check"
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: q)]
        return Target(url: c.url!, isOfficial: false, serial: .none, brandLabel: brandTerm)
    }
}
