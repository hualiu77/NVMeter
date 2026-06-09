import SwiftUI

/// Renders the menu-bar status item: BentoMark, optionally followed by the
/// hottest drive's current temperature.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsKeys.showTempInMenuBar) private var showTemp = true

    var body: some View {
        HStack(spacing: 3) {
            BentoMark(density: .compact, color: .primary)
                .frame(width: 16, height: 16)

            if showTemp, let temp = model.hottestTemp {
                Text("\(temp)°")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(menuTextColor)
            }
        }
    }

    /// Tint the digits with the hottest device's health color so a glance
    /// at the menu bar communicates urgency without opening the popover.
    private var menuTextColor: Color {
        if let level = model.hottestLevel, level == .critical || level == .warning {
            Theme.color(for: level)
        } else {
            .primary
        }
    }
}
