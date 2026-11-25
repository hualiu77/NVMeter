import Foundation
import AppKit
import IOKit
import NVMeterCore

/// Opens a user-initiated community report with only a small, allowlisted
/// diagnostic summary. The browser and clipboard share that same payload.
@MainActor
enum IssueReporter {

    /// Max URL length we'll attempt to embed in a single click. GitHub
    /// technically accepts ~8 KB but Safari truncates around this size.
    private static let maxURLBytes = 6000

    private static let drivedbRepo = "hualiu77/NVMeter-drivedb"

    /// Build the report and open it in the browser. Safe to call from
    /// the main thread; the diagnostic gathering runs off-actor.
    static func report(for snapshot: DeviceSnapshot) {
        let modelName = snapshot.modelName // Local history only.
        if let prev = ReportHistory.shared.lastReport(for: modelName),
           Date().timeIntervalSince(prev.lastReportedAt) < 30 * 24 * 3600,
           !confirmDuplicate(modelName: modelName, previous: prev) {
            return
        }

        let devicePath = snapshot.devicePath
        Task.detached {
            let report = EnclosureIssueReport(
                outcome: .blocked, bridge: usbBridge(for: devicePath),
                version: nvmeterVersion(), os: ProcessInfo.processInfo.operatingSystemVersion
            )
            await MainActor.run {
                openOrCopy(title: report.title, body: report.body)
                ReportHistory.shared.recordSubmission(model: modelName)
            }
        }
    }

    /// The positive counterpart to report: contribute the working probe type.
    static func contribute(for snapshot: DeviceSnapshot, workingArgs: [String]) {
        let devicePath = snapshot.devicePath
        Task.detached {
            let report = EnclosureIssueReport(
                outcome: .working(args: workingArgs), bridge: usbBridge(for: devicePath),
                version: nvmeterVersion(), os: ProcessInfo.processInfo.operatingSystemVersion
            )
            await MainActor.run { openOrCopy(title: report.title, body: report.body) }
        }
    }

    private static func confirmDuplicate(modelName: String, previous: ReportRecord) -> Bool {
        let daysAgo = Int(Date().timeIntervalSince(previous.lastReportedAt) / 86400)
        let alert = NSAlert()
        alert.messageText = String(localized: "Already reported", bundle: localizationBundle)
        alert.informativeText = String(localized:
            "You've already submitted \(previous.count) report(s) for **\(modelName)** — the most recent was \(daysAgo) day(s) ago. Are you sure you want to file another?",
            bundle: localizationBundle
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Submit anyway", bundle: localizationBundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: localizationBundle))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Open / copy fallback

    private static func openOrCopy(title: String, body: String) {
        let url = newIssueURL(title: title, body: body)
        let safe = url.absoluteString.lengthOfBytes(using: .utf8) <= maxURLBytes

        if safe {
            NSWorkspace.shared.open(url)
            return
        }

        // Body too big to fit in the URL — copy to clipboard FIRST, then
        // explain what's about to happen, and only open the browser after
        // the user acknowledges. (Opening the browser before the modal
        // made the instructions read like an afterthought behind Safari.)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(body, forType: .string)

        let alert = NSAlert()
        alert.messageText = String(localized: "Report copied to clipboard", bundle: localizationBundle)
        alert.informativeText = String(localized: "The full report didn't fit in a URL, so NVMeter copied it to the clipboard. Click OK to open the GitHub issue page, then paste (⌘V) into the description and submit.", bundle: localizationBundle)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "OK", bundle: localizationBundle))
        alert.runModal()

        let shortURL = newIssueURL(
            title: title,
            body: "_NVMeter's diagnostic report was too large for a URL; it's already on your clipboard. **Press ⌘V here.**_"
        )
        NSWorkspace.shared.open(shortURL)
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

    // MARK: - Allowlisted device lookup

    nonisolated private static func usbBridge(for path: String) -> EnclosureIssueReport.USBBridge? {
        let bsd = path.hasPrefix("/dev/") ? String(path.dropFirst(5)) : path
        guard bsd.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let matching = bsd.withCString({ IOBSDNameMatching(kIOMainPortDefault, 0, $0) }) else {
            return nil
        }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        // The nearest USB device in this disk's service ancestry is the
        // bridge. Never enumerate other USB devices or report parent hubs.
        while IOObjectConformsTo(entry, "IOUSBHostDevice") == 0 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0 else { return nil }
            IOObjectRelease(entry)
            entry = parent
        }

        return EnclosureIssueReport.USBBridge(
            vendorID: usbNumber(entry, key: "idVendor"),
            productID: usbNumber(entry, key: "idProduct")
        )
    }

    nonisolated private static func usbNumber(_ entry: io_registry_entry_t, key: String) -> Int? {
        let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? NSNumber)?.intValue
    }

    nonisolated private static func nvmeterVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
