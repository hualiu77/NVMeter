import SwiftUI
import AppKit

enum SettingsKeys {
    static let showTempInMenuBar = "showTempInMenuBar"
    static let warningTempC      = "warningTempC"
    static let criticalTempC     = "criticalTempC"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.showTempInMenuBar) private var showTemp = true
    @AppStorage(SettingsKeys.warningTempC)      private var warningTemp = 60
    @AppStorage(SettingsKeys.criticalTempC)     private var criticalTemp = 70

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            thresholdsTab
                .tabItem { Label("Thresholds", systemImage: "thermometer") }
            helpTab
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 420)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show temperature next to icon", isOn: $showTemp)
                    .help("Displays the hottest drive's temperature in the menu bar.")
            } header: {
                Text("Menu bar")
            } footer: {
                Text("When off, only the NVMeter icon is shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var thresholdsTab: some View {
        Form {
            Section {
                Stepper(value: $warningTemp, in: 40...85, step: 1) {
                    HStack {
                        Text("Warning")
                        Spacer()
                        Text("\(warningTemp) °C").monospacedDigit().foregroundStyle(.orange)
                    }
                }
                Stepper(value: $criticalTemp, in: 50...95, step: 1) {
                    HStack {
                        Text("Critical")
                        Spacer()
                        Text("\(criticalTemp) °C").monospacedDigit().foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Temperature thresholds")
            } footer: {
                Text("Defaults: green below warning, yellow between warning and critical, red at or above critical. Spec values for NVMe throttling vary by drive; these thresholds are conservative and match what most users want to see at a glance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: warningTemp) { _, newValue in
            if criticalTemp <= newValue { criticalTemp = newValue + 5 }
        }
    }

    private var helpTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                helpIntro
                helpItem("Temperature",
                         "Current drive temperature from the SMART log. NVMe drives typically throttle around 70 °C and signal critical around 80 °C. NVMeter's defaults (60/70) are conservative — adjust them in the Thresholds tab.")
                helpItem("Wear",
                         "The SSD's own estimate of NAND endurance consumed (the `percentage_used` SMART field). 0% means brand new; 100% means the drive has reached its manufacturer-rated total bytes written (TBW). Most drives keep working past 100% — the warranty just no longer covers it.")
                helpItem("Power-on",
                         "Cumulative hours the drive has been powered on since manufacture. Shutdown stops the counter; sleep with the drive still powered does not.")
                helpItem("Written",
                         "Total bytes the host has written to NAND since manufacture, derived from the NVMe `data_units_written` field × 500 KB per spec. Compare against the drive's TBW endurance rating to estimate remaining life — most consumer NVMe drives are rated for 200–1200 TBW per terabyte of capacity.")
                Divider().padding(.vertical, 4)
                helpItem("⚠️ Apple SSD quirks",
                         "Apple's NVMe controller reports SMART quite differently from third-party drives:\n\n• Wear stays at 0% almost indefinitely — the firmware uses coarse integer steps and Apple does not publish a TBW figure.\n• Power-on only counts S0 active state — sleep, Power Nap, and shutdown DO NOT count, so on a Mac that's rarely turned off this number can lag wall-clock time substantially.\n\nFor Apple SSDs, the Written tile is the most reliable signal of NAND wear.")
                helpItem("🟢 / 🟡 / 🔴 in the menu bar",
                         "Green when the hottest drive is below the warning threshold, yellow between warning and critical, red at or above critical. The temperature digit is also colored the same way (the dot is a backup, since macOS sometimes strips text colors from menu-bar items).")
                helpItem("\"SMART pass-through blocked by macOS\"",
                         "Many USB-SATA and USB-NVMe bridge chips do not expose SMART through macOS's SCSI stack — there is no third-party kernel extension you can install on Apple Silicon to fix this without disabling SIP. NVMeter still shows capacity, mount points, and connection info for these drives; if SMART is essential, attach the drive through a Thunderbolt enclosure (PCIe pass-through is unaffected).")
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private var helpIntro: some View {
        Text("What the numbers mean")
            .font(.title3.weight(.semibold))
    }

    private func helpItem(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutTab: some View {
        VStack(spacing: Theme.Spacing.m) {
            BentoMark()
                .frame(width: 64, height: 64)
            Text("NVMeter")
                .font(.title2.weight(.bold))
            Text("Open-source SMART monitor for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.m) {
                Link("GitHub", destination: URL(string: "https://github.com/hualiu77/NVMeter")!)
                Link("Bridge database", destination: URL(string: "https://github.com/hualiu77/NVMeter-drivedb")!)
                Link("Report a bug", destination: URL(string: "https://github.com/hualiu77/NVMeter/issues")!)
            }
            .font(.callout)
            Text("AGPL-3.0-or-later · uses smartmontools (GPL-2.0)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Brings the Settings window to the front reliably.
///
/// macOS 14's `openSettings()` opens / focuses the window only when the
/// app is already frontmost. Menu-bar apps are usually NOT frontmost, so
/// the window stays buried under whatever the user was just doing. We:
///   1. Activate this app (pulls all our windows toward the front),
///   2. Call `openSettings()` (creates the window if it doesn't exist),
///   3. On the next runloop tick, find the window by title and force it
///      forward — this handles the "window already exists but is hidden"
///      case that step 2 alone won't fix.
@MainActor
func showSettingsWindow(using openSettings: () -> Void) {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
    DispatchQueue.main.async {
        let candidates = NSApp.windows.filter { window in
            // SwiftUI's Settings scene names the window "Settings" (en) or
            // the localized equivalent. Match by being a non-status visible
            // window with a non-empty title, falling back to identifier.
            guard window.isVisible else { return false }
            if window.title.localizedCaseInsensitiveContains("Setting") { return true }
            if window.title.localizedCaseInsensitiveContains("Preference") { return true }
            if window.title == "NVMeter" { return false }  // not our popover
            return window.identifier?.rawValue.localizedCaseInsensitiveContains("setting") == true
        }
        for window in candidates {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

#Preview { SettingsView() }
