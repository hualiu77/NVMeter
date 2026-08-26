import SwiftUI

/// Local, per-drive purchase dates — keyed by serial number, stored in
/// UserDefaults. Combined with a model's rated warranty length, this lets
/// NVMeter show a warranty countdown entirely offline, which is the only
/// useful path for brands (Crucial, Samsung, …) that have no online
/// serial-number checker. Nothing leaves the machine.
final class PurchaseDateStore {
    static let shared = PurchaseDateStore()
    private let key = "purchaseDatesBySerial"

    func date(forSerial serial: String) -> Date? {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return map[serial].map { Date(timeIntervalSince1970: $0) }
    }

    func set(_ date: Date?, forSerial serial: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        map[serial] = date?.timeIntervalSince1970     // nil removes the key
        UserDefaults.standard.set(map, forKey: key)
    }
}

/// One line in the warranty card: enter a purchase date, then see when the
/// rated warranty runs out and how long is left — computed locally.
struct WarrantyCountdownRow: View {
    let serial: String
    let warrantyYears: Int

    @State private var date: Date?
    @State private var draft = Date()
    @State private var editing = false

    var body: some View {
        Group {
            if editing {
                editor
            } else if let date {
                summary(purchase: date)
            } else {
                Button {
                    draft = Date()
                    editing = true
                } label: {
                    Label(LR("Set purchase date for warranty countdown"), systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }
        .font(.caption)
        .onAppear { date = PurchaseDateStore.shared.date(forSerial: serial) }
    }

    private var editor: some View {
        HStack(spacing: Theme.Spacing.s) {
            DatePicker(LR("Purchase date"), selection: $draft, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Button(LR("Save")) {
                date = draft
                PurchaseDateStore.shared.set(draft, forSerial: serial)
                editing = false
            }
            .controlSize(.small)
            Button(LR("Cancel")) { editing = false }
                .controlSize(.small)
        }
    }

    private func summary(purchase: Date) -> some View {
        let end = Calendar.current.date(byAdding: .year, value: warrantyYears, to: purchase) ?? purchase
        let expired = end <= Date()
        let endStr = end.formatted(date: .abbreviated, time: .omitted)
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full

        return HStack(spacing: 6) {
            Image(systemName: expired ? "exclamationmark.shield.fill" : "shield.fill")
                .imageScale(.small)
                .foregroundStyle(expired ? .red : .green)
            if expired {
                Text(String(localized: "Warranty expired \(endStr)", bundle: localizationBundle))
                    .foregroundStyle(.red)
            } else {
                Text(String(localized: "Warranty until \(endStr) · \(rel.localizedString(for: end, relativeTo: Date()))", bundle: localizationBundle))
            }
            Spacer()
            Button { draft = purchase; editing = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).controlSize(.small)
                .help(L("Change purchase date"))
            Button {
                date = nil
                PurchaseDateStore.shared.set(nil, forSerial: serial)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).controlSize(.small)
                .help(L("Clear purchase date"))
        }
        .foregroundStyle(.secondary)
    }
}
