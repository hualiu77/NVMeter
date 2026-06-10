import Foundation
import SwiftUI
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller.
///
/// One instance lives for the app's lifetime (created by NVMeterApp).
/// Settings binds to `automaticallyChecksForUpdates` and calls
/// `checkForUpdates()` from the "Check Now" button.
@MainActor
final class UpdaterManager: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors the updater's canCheckForUpdates for button enablement.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → Sparkle schedules its own background
        // checks per SUEnableAutomaticChecks / user defaults.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    func checkForUpdates() {
        // The update window is a regular window; menu-bar apps need the
        // same activation-policy bump Settings does or it opens buried.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
