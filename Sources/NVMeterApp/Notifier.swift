import Foundation
import UserNotifications
import NVMeterCore

/// Posts macOS system notifications when a device crosses temperature or
/// wear thresholds. Debounced so we don't spam the user every poll cycle.
@MainActor
final class Notifier {
    static let shared = Notifier()

    /// Per-device last-fired timestamps keyed by stable device path.
    private var lastFiredByDevice: [String: Date] = [:]
    /// Per-device last-known level, so we only fire on transitions.
    private var lastLevelByDevice: [String: NotifiedLevel] = [:]

    private let debounceInterval: TimeInterval = 5 * 60   // 5 minutes
    private var requestedPermission = false

    enum NotifiedLevel: String { case ok, warning, critical }

    /// Called from AppModel after each scan. Snapshots already carry the
    /// thresholds-applied health level from HealthScorer; we just decide
    /// whether to fire a system notification.
    func evaluate(_ snapshots: [DeviceSnapshot], settings: NotificationSettings) async {
        guard settings.enabled else { return }
        await ensurePermission()

        let now = Date()
        for snap in snapshots {
            // Only fire for healthy (non-blocked) devices with a real temp.
            guard !snap.isBlocked, let temp = snap.temperatureC else { continue }

            let level = classify(temp: temp, settings: settings)
            let previous = lastLevelByDevice[snap.devicePath] ?? .ok
            lastLevelByDevice[snap.devicePath] = level

            // Fire only on transitions UP (.ok→.warning, .ok→.critical,
            // .warning→.critical). Returning to .ok stays silent.
            guard level != .ok, level.severity > previous.severity else { continue }

            // Debounce: don't re-fire the same level for the same device
            // within the debounce window even if the user dismissed it.
            if let last = lastFiredByDevice[snap.devicePath],
               now.timeIntervalSince(last) < debounceInterval { continue }

            await fire(snapshot: snap, level: level)
            lastFiredByDevice[snap.devicePath] = now
        }
    }

    /// Posts a notification when an extended self-test finishes. Not
    /// debounced — a self-test completion is a discrete, user-initiated
    /// event, so it always deserves to surface.
    func selfTestFinished(deviceName: String, passed: Bool?, resultLabel: String) async {
        await ensurePermission()
        let content = UNMutableNotificationContent()
        switch passed {
        case .some(true):
            content.title = "✅ " + String(localized: "\(deviceName) passed its self-test", bundle: localizationBundle)
        case .some(false):
            content.title = "🔴 " + String(localized: "\(deviceName) FAILED its self-test", bundle: localizationBundle)
            content.sound = .defaultCritical
        case .none:
            content.title = "⚠️ " + String(localized: "\(deviceName) self-test ended", bundle: localizationBundle)
        }
        content.body = resultLabel
        if content.sound == nil { content.sound = .default }
        content.threadIdentifier = "nvmeter.selftest.\(deviceName)"

        let request = UNNotificationRequest(
            identifier: "nvmeter.selftest.\(deviceName).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Internals

    private func classify(temp: Int, settings: NotificationSettings) -> NotifiedLevel {
        if temp >= settings.criticalC { return .critical }
        if temp >= settings.warningC  { return .warning }
        return .ok
    }

    private func ensurePermission() async {
        guard !requestedPermission else { return }
        requestedPermission = true
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            // Permission denied or system error — quietly skip; user can
            // grant later via System Settings → Notifications.
        }
    }

    private func fire(snapshot: DeviceSnapshot, level: NotifiedLevel) async {
        let content = UNMutableNotificationContent()
        if level == .critical {
            content.title = "🔴 " + String(localized: "\(snapshot.modelName) is hot", bundle: localizationBundle)
        } else {
            content.title = "🟡 " + String(localized: "\(snapshot.modelName) is warming up", bundle: localizationBundle)
        }
        if let temp = snapshot.temperatureC {
            content.body = String(localized: "Drive temperature is \(temp) °C.", bundle: localizationBundle)
        }
        content.sound = level == .critical ? .defaultCritical : .default
        content.threadIdentifier = "nvmeter.device.\(snapshot.devicePath)"

        let request = UNNotificationRequest(
            identifier: "nvmeter.\(snapshot.devicePath).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

private extension Notifier.NotifiedLevel {
    var severity: Int {
        switch self { case .ok: 0; case .warning: 1; case .critical: 2 }
    }
}

/// Snapshot of notification-relevant settings, passed in from AppModel so
/// the Notifier doesn't reach into @AppStorage from its actor context.
struct NotificationSettings {
    let enabled: Bool
    let warningC: Int
    let criticalC: Int
}
