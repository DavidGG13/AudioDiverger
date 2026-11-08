import SwiftUI

struct RoutingView: View {
    @EnvironmentObject private var model: AudioModel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.visibleApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app, compact: compact)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("AudioDiverger").font(.headline)
                Text("Ieșire implicită: \(model.defaultDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Doar active", isOn: $model.onlyActive)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Arată doar aplicațiile care redau audio sau au o rută setată")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Nicio aplicație audio")
                .font(.headline)
            Text("Pornește redarea într-o aplicație (browser, DaVinci, Spotify…) și va apărea aici.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Pornește la login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Spacer()
            Button("Resetează tot") { model.resetAll() }
                .controlSize(.small)
                .disabled(model.assignments.isEmpty)
            if compact {
                Button("Ieșire") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct AppRow: View {
    @EnvironmentObject private var model: AudioModel
    let app: AudioApp
    var compact = false

    private var assigned: String { model.assignedDeviceUID(for: app.id) }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                status
            }

            Spacer(minLength: 8)

            if model.isRouted(app.id) && !compact {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(model.volume(for: app.id)) },
                        set: { model.setVolume(Float($0), for: app.id) }), in: 0...1)
                        .controlSize(.mini)
                        .frame(width: 80)
                }
                .help("Volum pentru această aplicație")
            }

            devicePicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(model.isRouted(app.id) ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var status: some View {
        if let error = model.errors[app.id] {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if !assigned.isEmpty && !model.isConnected(uid: assigned) {
            Label("\(model.deviceName(forUID: assigned)) deconectat – redă pe implicit",
                  systemImage: "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            HStack(spacing: 5) {
                Circle()
                    .fill(app.isPlaying ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(app.isPlaying ? "Redă audio" : "Inactivă")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var devicePicker: some View {
        Picker("", selection: Binding(
            get: { assigned },
            set: { model.setDevice($0, for: app.id) })) {
            Label("Implicit (\(model.defaultDeviceName))", systemImage: "arrow.uturn.backward")
                .tag("")
            Divider()
            ForEach(model.devices) { device in
                Label(device.name, systemImage: device.symbol).tag(device.uid)
            }
            if !assigned.isEmpty && !model.isConnected(uid: assigned) {
                Label("\(model.deviceName(forUID: assigned)) (deconectat)", systemImage: "bolt.horizontal.circle")
                    .tag(assigned)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: compact ? 170 : 220)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var model: AudioModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            RoutingView(compact: true)
            Divider()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Deschide fereastra", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 430, height: 440)
    }
}
