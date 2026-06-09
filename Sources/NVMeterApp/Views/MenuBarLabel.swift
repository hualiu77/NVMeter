import SwiftUI

/// Menu-bar status item: BentoMark, optionally followed by the hottest
/// drive's current temperature, colored green/yellow/red against
/// user-configurable thresholds.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage(SettingsKeys.showTempInMenuBar) private var showTemp = true
    @AppStorage(SettingsKeys.warningTempC)      private var warningTemp = 60
    @AppStorage(SettingsKeys.criticalTempC)     private var criticalTemp = 70

    var body: some View {
        HStack(spacing: 3) {
            BentoMark(density: .compact, color: .primary)
                .frame(width: 16, height: 16)

            if showTemp, let temp = model.hottestTemp {
                Text("\(temp)°")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(color(forTemp: temp))
            }
        }
    }

    /// <warn → green, [warn, crit) → yellow, ≥crit → red.
    private func color(forTemp temp: Int) -> Color {
        if temp < warningTemp { .green }
        else if temp < criticalTemp { .yellow }
        else { .red }
    }
}
