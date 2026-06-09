import Foundation

/// Small lookup table for PCI vendor IDs commonly seen in NVMe SSDs.
/// Source: PCI-SIG vendor list + NVMe drives' typical controller vendors.
/// Extend by PR — vendor IDs are public domain data.
public enum PCIVendor {
    private static let table: [UInt32: String] = [
        0x144D: "Samsung",
        0x1344: "Crucial / Micron",
        0x15B7: "Western Digital / SanDisk",
        0x1B4B: "Marvell",
        0x14A4: "Phison",
        0x1987: "Phison",
        0x1C5C: "SK hynix",
        0x126F: "Silicon Motion",
        0x1E0F: "Solidigm",
        0x1B96: "Western Digital",
        0x8086: "Intel",
        0x10EC: "Realtek",
        0x196E: "PNY",
        0x1E4B: "MAXIO",
        0x1CC4: "UMIS / Unigroup",
        0x1CC1: "ADATA",
        0x025E: "Solid State Storage Technology",
        0x106B: "Apple",
        0x1D97: "Lexar",
        0x1F9F: "MaxioTech",
    ]

    /// Returns a friendly brand name for a PCI vendor ID, or nil if unknown.
    public static func name(forID id: UInt32) -> String? { table[id] }
}
