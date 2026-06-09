import SwiftUI

/// Menu-bar status item.
///
/// macOS aggressively templates `MenuBarExtra` label content — SwiftUI
/// `Shape` fills and `.foregroundStyle()` on text are silently dropped
/// down to the menu-bar's text color. The reliable way to show color
/// is to use **emoji glyphs**, which are stored as colored bitmaps in
/// the system font and survive template treatment unchanged.
///
/// So the dot we render is `🟢 / 🟡 / 🔴` rather than a SwiftUI Circle.
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
                Text(menuText(for: temp))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
    }

    private func menuText(for temp: Int) -> String {
        let dot: String
        if temp >= criticalTemp { dot = "🔴" }
        else if temp >= warningTemp { dot = "🟡" }
        else { dot = "🟢" }
        return "\(dot) \(temp)°"
    }
}
