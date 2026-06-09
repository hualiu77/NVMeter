import SwiftUI

enum SettingsKeys {
    static let showTempInMenuBar = "showTempInMenuBar"
    static let warningTempC      = "warningTempC"
    static let criticalTempC     = "criticalTempC"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.showTempInMenuBar) private var showTemp = true
    @AppStorage(SettingsKeys.warningTempC)      private var warningTemp = 60
    @AppStorage(SettingsKeys.criticalTempC)     private var criticalTemp = 80

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            thresholdsTab
                .tabItem { Label("Thresholds", systemImage: "thermometer") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 280)
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
                Text("NVMe drives typically throttle around 70 °C and signal critical around 80 °C. Defaults match the NVMe spec recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: warningTemp) { _, newValue in
            if criticalTemp <= newValue { criticalTemp = newValue + 5 }
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

#Preview { SettingsView() }
