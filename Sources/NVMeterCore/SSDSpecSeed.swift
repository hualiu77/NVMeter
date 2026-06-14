import Foundation

// Seed spec data, transcribed from manufacturers' public datasheets
// (TBW rating + limited-warranty length, per capacity). Keyed by SMART
// model-name substrings — never by serial number.
//
// This is the project-maintained starting set covering common consumer
// NVMe/SATA drives. It is NOT exhaustive: a user/community override at
// ~/Library/Application Support/NVMeter/ssd-specs/*.yaml takes precedence
// (see SSDSpecDatabase.loadDefault), and the long tail is meant to be
// extended there / in a future CC0 repo. Found a wrong number? It's a
// one-line fix — please correct it.
//
// Warranty years are the manufacturer's *limited warranty* length; actual
// remaining coverage also depends on purchase date, which SMART can't know.
extension SSDSpecDatabase {
    public static let builtInSeed: [SSDSpec] = [
        // ── Crucial / Micron ─────────────────────────────────────────────
        // P3 & P3 Plus (QLC) — same TBW per capacity.
        SSDSpec(model_match: ["CT500P3"],  brand: "Crucial", series: "P3 / P3 Plus", tbw: 110, warranty_years: 5),
        SSDSpec(model_match: ["CT1000P3"], brand: "Crucial", series: "P3 / P3 Plus", tbw: 220, warranty_years: 5),
        SSDSpec(model_match: ["CT2000P3"], brand: "Crucial", series: "P3 / P3 Plus", tbw: 440, warranty_years: 5),
        SSDSpec(model_match: ["CT4000P3"], brand: "Crucial", series: "P3 / P3 Plus", tbw: 800, warranty_years: 5),
        // T500 (TLC, Gen4)
        SSDSpec(model_match: ["CT500T500"],  brand: "Crucial", series: "T500", tbw: 300,  warranty_years: 5),
        SSDSpec(model_match: ["CT1000T500"], brand: "Crucial", series: "T500", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["CT2000T500"], brand: "Crucial", series: "T500", tbw: 1200, warranty_years: 5),
        // MX500 (SATA TLC)
        SSDSpec(model_match: ["CT250MX500"],  brand: "Crucial", series: "MX500", tbw: 100,  warranty_years: 5),
        SSDSpec(model_match: ["CT500MX500"],  brand: "Crucial", series: "MX500", tbw: 180,  warranty_years: 5),
        SSDSpec(model_match: ["CT1000MX500"], brand: "Crucial", series: "MX500", tbw: 360,  warranty_years: 5),
        SSDSpec(model_match: ["CT2000MX500"], brand: "Crucial", series: "MX500", tbw: 700,  warranty_years: 5),

        // ── Samsung ──────────────────────────────────────────────────────
        SSDSpec(model_match: ["990 PRO 1TB"], brand: "Samsung", series: "990 PRO", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["990 PRO 2TB"], brand: "Samsung", series: "990 PRO", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["990 PRO 4TB"], brand: "Samsung", series: "990 PRO", tbw: 2400, warranty_years: 5),
        SSDSpec(model_match: ["980 PRO 500GB"], brand: "Samsung", series: "980 PRO", tbw: 300,  warranty_years: 5),
        SSDSpec(model_match: ["980 PRO 1TB"],   brand: "Samsung", series: "980 PRO", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["980 PRO 2TB"],   brand: "Samsung", series: "980 PRO", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["970 EVO Plus 500GB"], brand: "Samsung", series: "970 EVO Plus", tbw: 300,  warranty_years: 5),
        SSDSpec(model_match: ["970 EVO Plus 1TB"],   brand: "Samsung", series: "970 EVO Plus", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["970 EVO Plus 2TB"],   brand: "Samsung", series: "970 EVO Plus", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["870 EVO 500GB"], brand: "Samsung", series: "870 EVO", tbw: 300,  warranty_years: 5),
        SSDSpec(model_match: ["870 EVO 1TB"],   brand: "Samsung", series: "870 EVO", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["870 EVO 2TB"],   brand: "Samsung", series: "870 EVO", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["870 EVO 4TB"],   brand: "Samsung", series: "870 EVO", tbw: 2400, warranty_years: 5),

        // ── Western Digital / SanDisk ────────────────────────────────────
        SSDSpec(model_match: ["SN850X 1000GB", "SN850X 1TB"], brand: "Western Digital", series: "WD_BLACK SN850X", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["SN850X 2000GB", "SN850X 2TB"], brand: "Western Digital", series: "WD_BLACK SN850X", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["SN850X 4000GB", "SN850X 4TB"], brand: "Western Digital", series: "WD_BLACK SN850X", tbw: 2400, warranty_years: 5),
        SSDSpec(model_match: ["SN770 500GB"],            brand: "Western Digital", series: "WD_BLACK SN770", tbw: 300,  warranty_years: 5),
        SSDSpec(model_match: ["SN770 1000GB", "SN770 1TB"], brand: "Western Digital", series: "WD_BLACK SN770", tbw: 600,  warranty_years: 5),
        SSDSpec(model_match: ["SN770 2000GB", "SN770 2TB"], brand: "Western Digital", series: "WD_BLACK SN770", tbw: 1200, warranty_years: 5),
        SSDSpec(model_match: ["SN570 500GB"],            brand: "Western Digital", series: "WD Blue SN570", tbw: 300, warranty_years: 5),
        SSDSpec(model_match: ["SN570 1000GB", "SN570 1TB"], brand: "Western Digital", series: "WD Blue SN570", tbw: 600, warranty_years: 5),

        // ── Kingston ─────────────────────────────────────────────────────
        SSDSpec(model_match: ["SNV2S500G"],  brand: "Kingston", series: "NV2", tbw: 160, warranty_years: 3),
        SSDSpec(model_match: ["SNV2S1000G"], brand: "Kingston", series: "NV2", tbw: 320, warranty_years: 3),
        SSDSpec(model_match: ["SNV2S2000G"], brand: "Kingston", series: "NV2", tbw: 640, warranty_years: 3),

        // ── Seagate ──────────────────────────────────────────────────────
        SSDSpec(model_match: ["ZP1000GM30013"], brand: "Seagate", series: "FireCuda 530", tbw: 1275, warranty_years: 5),
        SSDSpec(model_match: ["ZP2000GM30013"], brand: "Seagate", series: "FireCuda 530", tbw: 2550, warranty_years: 5),
    ]
}
