import Foundation
import Yams

/// Published endurance / warranty terms for a drive model, transcribed from
/// the manufacturer's public datasheet — keyed by **model name**, never by
/// serial number. This is factual spec data (TBW rating, warranty length),
/// so it carries no privacy implications and needs no network: NVMeter reads
/// the model from SMART and looks it up locally.
///
/// Seeded by the project with mainstream consumer models, then extended by
/// the community (CC0), the same one-YAML-PR model as the bridge database.
public struct SSDSpec: Codable, Sendable, Equatable {
    /// Case-insensitive substrings matched against the SMART `model_name`.
    /// Make these capacity-specific (e.g. "CT1000P3", "990 PRO 2TB") so the
    /// right TBW maps to the right capacity. The longest match wins.
    public let model_match: [String]
    public let brand: String
    public let series: String?
    /// Rated total bytes written, in terabytes, for this capacity.
    public let tbw: Int?
    /// Manufacturer's limited-warranty length in years.
    public let warranty_years: Int?
    public let notes: String?

    public init(model_match: [String], brand: String, series: String? = nil,
                tbw: Int? = nil, warranty_years: Int? = nil, notes: String? = nil) {
        self.model_match = model_match
        self.brand = brand
        self.series = series
        self.tbw = tbw
        self.warranty_years = warranty_years
        self.notes = notes
    }

    /// Fraction of rated endurance consumed, given lifetime host writes.
    /// Nil when this model has no published TBW (e.g. Apple SSDs).
    public func usedEnduranceFraction(lifetimeWrittenBytes: Int64) -> Double? {
        guard let tbw, tbw > 0, lifetimeWrittenBytes > 0 else { return nil }
        return Double(lifetimeWrittenBytes) / (Double(tbw) * 1_000_000_000_000)
    }
}

public struct SSDSpecDatabase: Sendable {
    public let specs: [SSDSpec]

    public init(specs: [SSDSpec]) { self.specs = specs }
    public static let empty = SSDSpecDatabase(specs: [])

    /// Best match for a SMART model string: the spec whose longest
    /// `model_match` token is contained in the model name. Longest-token
    /// wins so a specific entry ("CT1000P3PSSD8") beats a generic one
    /// ("CT1000P3"), and a generic one still catches unseen variants.
    public func lookup(model: String) -> SSDSpec? {
        let haystack = model.uppercased()
        var best: (spec: SSDSpec, len: Int)?
        for spec in specs {
            for token in spec.model_match {
                let t = token.uppercased()
                guard haystack.contains(t) else { continue }
                if best == nil || t.count > best!.len {
                    best = (spec, t.count)
                }
            }
        }
        return best?.spec
    }

    /// The default spec set: a community/user override dropped in
    /// `~/Library/Application Support/NVMeter/ssd-specs/*.yaml` if present,
    /// otherwise the seed compiled into the app (`builtInSeed`). Compiling
    /// the seed in means it works identically in `swift run` and the bundle
    /// with no build-script plumbing, while the override path still lets the
    /// community extend coverage without an app update.
    public static func loadDefault() -> SSDSpecDatabase {
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) {
            let dir = support.appendingPathComponent("NVMeter/ssd-specs", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue,
               let db = try? load(directory: dir), !db.specs.isEmpty {
                return db
            }
        }
        return SSDSpecDatabase(specs: builtInSeed)
    }

    /// Load and merge every `.yaml` under `directory`. Each file is a YAML
    /// sequence of `SSDSpec`.
    public static func load(directory: URL) throws -> SSDSpecDatabase {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return .empty
        }
        let decoder = YAMLDecoder()
        var specs: [SSDSpec] = []
        for url in items where url.pathExtension == "yaml" || url.pathExtension == "yml" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = try? decoder.decode([SSDSpec].self, from: text)
            else { continue }
            specs.append(contentsOf: parsed)
        }
        return SSDSpecDatabase(specs: specs)
    }
}
