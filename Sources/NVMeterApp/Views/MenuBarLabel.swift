import SwiftUI
import NVMeterCore

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
    @AppStorage(SettingsKeys.showTempInMenuBar) private var showMetric = true
    @AppStorage(SettingsKeys.menuBarMetric)     private var metricRaw = MenuBarMetric.temperature.rawValue
    @AppStorage(SettingsKeys.warningTempC)      private var warningTemp = 60
    @AppStorage(SettingsKeys.criticalTempC)     private var criticalTemp = 70

    private var metric: MenuBarMetric { MenuBarMetric(rawValue: metricRaw) ?? .temperature }

    var body: some View {
        HStack(spacing: 3) {
            BentoMark(density: .compact, color: .primary)
                .frame(width: 16, height: 16)

            if showMetric, let text = metricText() {
                Text(text)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
    }

    /// Nil when the chosen metric has no data yet (e.g. wear before the
    /// first scan), in which case we show the bare icon.
    private func metricText() -> String? {
        switch metric {
        case .temperature:
            guard let temp = model.hottestTemp else { return nil }
            return "\(tempDot(temp)) \(temp)°"
        case .wear:
            guard let wear = model.highestWear else { return nil }
            return "\(wearDot(wear)) \(wear)%"
        case .health:
            guard let level = model.hottestLevel else { return nil }
            return healthDot(level)
        }
    }

    private func tempDot(_ temp: Int) -> String {
        if temp >= criticalTemp { return "🔴" }
        if temp >= warningTemp  { return "🟡" }
        return "🟢"
    }

    /// Wear bands mirror the health scorer: ≥90% critical, ≥70% warning.
    private func wearDot(_ wear: Int) -> String {
        if wear >= 90 { return "🔴" }
        if wear >= 70 { return "🟡" }
        return "🟢"
    }

    private func healthDot(_ level: HealthLevel) -> String {
        switch level {
        case .good:     "🟢"
        case .warning:  "🟡"
        case .critical: "🔴"
        case .unknown:  "⚪️"
        }
    }
}
