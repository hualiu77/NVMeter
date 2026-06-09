import SwiftUI
import NVMeterCore

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Theme.Layout.windowWidth)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            BentoMark()
                .frame(width: 22, height: 22)
            Text("NVMeter")
                .font(.title3.weight(.bold))
            Spacer()
            if let last = model.lastUpdated {
                Text(last, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    @ViewBuilder
    private var content: some View {
        if let err = model.lastError, model.devices.isEmpty {
            errorState(err)
        } else if model.devices.isEmpty {
            loadingState
        } else {
            // ScrollView collapses to zero height inside a self-sizing
            // MenuBarExtra(.window) popover, so we lay out devices in a
            // plain VStack and let the window size to content. With many
            // devices we'll add a properly-bounded ScrollView later.
            VStack(spacing: Theme.Spacing.m) {
                ForEach(model.devices) { device in
                    DeviceCard(snapshot: device)
                }
            }
            .padding(Theme.Spacing.l)
        }
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.s) {
            ProgressView()
                .controlSize(.small)
            Text("Reading SMART data…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Could not read SMART data", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Make sure smartmontools is installed:\n  brew install smartmontools")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await model.refreshNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)

            Spacer()

            Button {
                showSettingsWindow(using: { openSettings() })
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit NVMeter")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
    }
}
