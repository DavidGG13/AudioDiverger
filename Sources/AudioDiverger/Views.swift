import AppKit
import SwiftUI

// MARK: - Root

struct RoutingView: View {
    enum Style { case popover, window }

    @EnvironmentObject private var model: AudioModel
    var style: Style = .popover
    @State private var showInactive = false

    var body: some View {
        VStack(spacing: 0) {
            PresetBar()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            if model.apps.isEmpty {
                EmptyState()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.activeApps) { app in
                            TrackRow(app: app)
                        }
                        if model.activeApps.isEmpty {
                            Text("Nothing is playing right now.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                        if !model.inactiveApps.isEmpty {
                            InactiveSection(apps: model.inactiveApps, expanded: $showInactive)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
            }

            Divider()

            Footer(style: style)
        }
        .frame(height: style == .popover ? popoverHeight : nil)
        .background(VisibilityReporter { model.surfaceVisibilityChanged($0) })
    }

    /// The popover hugs its content (like Control Center modules) instead of
    /// leaving a fixed empty canvas, and scrolls past ~560pt.
    private var popoverHeight: CGFloat {
        let chrome: CGFloat = 46 + 38
        guard !model.apps.isEmpty else { return chrome + 170 }
        let rows = CGFloat(model.activeApps.count + (showInactive ? model.inactiveApps.count : 0))
        let nothingPlaying: CGFloat = model.activeApps.isEmpty ? 54 : 0
        let inactiveHeader: CGFloat = model.inactiveApps.isEmpty ? 0 : 34
        return min(max(chrome + 12 + rows * 48 + nothingPlaying + inactiveHeader, 200), 560)
    }
}

// MARK: - Scenes

private struct PresetBar: View {
    @EnvironmentObject private var model: AudioModel
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 6) {
            if model.presets.isEmpty {
                Text("Scenes")
                    .font(.subheadline.weight(.semibold))
                Text("save your routes and switch them in one click")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                            PresetChip(preset: preset, index: index,
                                       isActive: model.activePresetID == preset.id)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            Button {
                newName = ""
                naming = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Save the current routes as a new scene")
            .accessibilityLabel("New scene")
            .popover(isPresented: $naming, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("New scene").font(.headline)
                    TextField("e.g. Editing", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(save)
                    Text("Saves the outputs and mutes of every app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 200, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { naming = false }
                        Button("Save", action: save)
                            .keyboardShortcut(.defaultAction)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
            }
        }
        .frame(height: 26)
    }

    private func save() {
        model.saveCurrentAsPreset(named: newName)
        naming = false
    }
}

private struct PresetChip: View {
    @EnvironmentObject private var model: AudioModel
    let preset: Preset
    let index: Int
    let isActive: Bool

    var body: some View {
        Button {
            model.applyPreset(preset)
        } label: {
            HStack(spacing: 5) {
                Text(preset.name)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                if index < 9 {
                    Text("\(HotKeyCenter.modifierSymbols)\(index + 1)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? AnyShapeStyle(.primary.opacity(0.7)) : AnyShapeStyle(.tertiary))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(index < 9 ? "Apply scene (\(HotKeyCenter.modifierSymbols)\(index + 1))" : "Apply scene")
        .accessibilityLabel("Scene \(preset.name)\(isActive ? ", active" : "")")
        .contextMenu {
            Button("Update with current routes") { model.updatePreset(preset.id) }
            Divider()
            Button("Delete scene", role: .destructive) { model.deletePreset(preset.id) }
        }
    }
}

// MARK: - Track

struct TrackRow: View {
    @EnvironmentObject private var model: AudioModel
    let app: AudioApp
    @State private var hovering = false

    private var uids: [String] { model.assignedUIDs(for: app.id) }
    private var muted: Bool { model.isMuted(app.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .opacity(muted ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(muted ? .secondary : .primary)
                StatusLine(app: app)
            }

            Spacer(minLength: 6)

            DestinationButton(app: app)

            MuteButton(isMuted: muted) { model.toggleMute(app.id) }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .overlay(alignment: .bottom) {
            LevelMeter(appID: app.id, colors: meterColors, active: app.isPlaying && !muted)
                .padding(.leading, 44)
                .padding(.trailing, 10)
                .padding(.bottom, 3)
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var meterColors: [Color] {
        let connected = uids.filter(model.isConnected(uid:))
        if connected.isEmpty { return [.secondary] }
        return connected.map { model.color(forUID: $0) }
    }
}

private struct StatusLine: View {
    @EnvironmentObject private var model: AudioModel
    let app: AudioApp

    var body: some View {
        Group {
            if let error = model.errors[app.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .help(error)
            } else if let missing = model.assignedUIDs(for: app.id).first(where: { !model.isConnected(uid: $0) }) {
                Label("\(model.deviceName(forUID: missing)) disconnected", systemImage: "bolt.horizontal.circle")
                    .foregroundStyle(Color(nsColor: .systemOrange))
            } else if model.isMuted(app.id) {
                Text("Muted").foregroundStyle(.secondary)
            } else if app.isPlaying {
                Text("Playing").foregroundStyle(.secondary)
            } else {
                Text("Idle").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .labelStyle(CompactLabelStyle())
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

private struct MuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("M")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isMuted ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isMuted ? Color(nsColor: .systemRed) : Color.primary.opacity(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        .accessibilityAddTraits(isMuted ? .isSelected : [])
    }
}

// MARK: - Destination

private struct DestinationButton: View {
    @EnvironmentObject private var model: AudioModel
    let app: AudioApp
    @State private var open = false

    private var uids: [String] { model.assignedUIDs(for: app.id) }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                if let first = uids.first {
                    DeviceChip(name: model.deviceName(forUID: first),
                               color: model.color(forUID: first),
                               dimmed: !model.isConnected(uid: first))
                    if uids.count > 1 {
                        Text("+\(uids.count - 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                } else {
                    DeviceChip(name: "Default", color: nil, dimmed: false)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Output: \(uids.isEmpty ? "system default" : uids.map(model.deviceName(forUID:)).joined(separator: ", "))")
        .help("Choose where \(app.name) plays")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            DestinationPanel(app: app)
                .environmentObject(model)
        }
    }
}

private struct DeviceChip: View {
    let name: String
    let color: Color?
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color ?? .clear)
                .overlay(Circle().strokeBorder(color == nil ? Color.secondary : .clear, lineWidth: 1.2))
                .frame(width: 7, height: 7)
            Text(name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
        .opacity(dimmed ? 0.5 : 1)
    }
}

private struct DestinationPanel: View {
    @EnvironmentObject private var model: AudioModel
    let app: AudioApp

    private var uids: [String] { model.assignedUIDs(for: app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                Text(app.name).font(.headline).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PanelRow(title: "Default",
                     subtitle: model.defaultDevice.map { "follows the system · \($0.name)" } ?? "follows the system",
                     color: nil, symbol: "arrow.uturn.backward",
                     checked: uids.isEmpty) {
                model.setDevices([], for: app.id)
            }

            Divider().padding(.vertical, 4).padding(.horizontal, 14)

            ForEach(model.devices) { device in
                PanelRow(title: device.name, subtitle: nil,
                         color: model.color(forUID: device.uid), symbol: device.symbol,
                         checked: uids.contains(device.uid)) {
                    model.toggleDevice(device.uid, for: app.id)
                }
            }
            ForEach(uids.filter { !model.isConnected(uid: $0) }, id: \.self) { uid in
                PanelRow(title: model.deviceName(forUID: uid), subtitle: "disconnected",
                         color: model.color(forUID: uid), symbol: "bolt.horizontal.circle",
                         checked: true) {
                    model.toggleDevice(uid, for: app.id)
                }
            }

            Text("Tick several devices to play on all of them at once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            Divider().padding(.vertical, 10).padding(.horizontal, 14)

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(model.volume(for: app.id)) },
                    set: { model.setVolume(Float($0), for: app.id) }), in: 0...1)
                    .controlSize(.small)
                    .disabled(uids.isEmpty)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                Text("\(Int((model.volume(for: app.id) * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .accessibilityLabel("\(app.name) volume")
            if uids.isEmpty {
                Text("Volume applies once you pick a device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 14)
        .frame(width: 290)
    }
}

private struct PanelRow: View {
    let title: String
    let subtitle: String?
    let color: Color?
    let symbol: String
    let checked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(checked ? 1 : 0)
                    .frame(width: 12)
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(color ?? .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.body).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

// MARK: - Meter

/// Thin level line along the bottom of a track, in the destination colour(s).
/// Only animates while visible and while the app is actually sounding.
private struct LevelMeter: View {
    @EnvironmentObject private var model: AudioModel
    let appID: String
    let colors: [Color]
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active || !model.isMetering)) { _ in
            GeometryReader { geo in
                let level = active ? Self.display(model.level(for: appID)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(active ? 0.06 : 0))
                    Capsule()
                        .fill(LinearGradient(colors: colors.count > 1 ? colors : [colors[0], colors[0]],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(level)))
                        .opacity(colors.count == 1 && colors[0] == .secondary ? 0.55 : 0.9)
                }
            }
        }
        .frame(height: 2.5)
        .accessibilityHidden(true)
    }

    /// Map linear peak to a −54…0 dB scale so quiet audio still registers.
    private static func display(_ linear: Float) -> Double {
        guard linear > 0.000_01 else { return 0 }
        let db = 20 * log10(Double(linear))
        return min(max((db + 54) / 54, 0), 1)
    }
}

// MARK: - Inactive, empty, footer

private struct InactiveSection: View {
    let apps: [AudioApp]
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Idle")
                        .font(.caption.weight(.semibold))
                    Text("\(apps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Idle apps, \(apps.count)")
            .accessibilityValue(expanded ? "expanded" : "collapsed")

            if expanded {
                ForEach(apps) { TrackRow(app: $0) }
            }
        }
        .padding(.top, 4)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No audio apps yet")
                .font(.headline)
            Text("Play something in any app (DaVinci, a browser, Spotify) and it shows up here as a track.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct Footer: View {
    @EnvironmentObject private var model: AudioModel
    @Environment(\.openWindow) private var openWindow
    let style: RoutingView.Style

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.defaultDevice?.symbol ?? "speaker.wave.2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Default: \(model.defaultDevice?.name ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)

            if style == .popover {
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: {
                    Image(systemName: "macwindow").frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Open window")
                .accessibilityLabel("Open window")
            }

            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
                Button("Reset all routes") { model.resetRoutes() }
                    .disabled(model.assignments.isEmpty && model.muted.isEmpty)
                Divider()
                Button("Quit AudioDiverger") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Visibility

/// Reports when the hosting window is actually on screen, so metering (the
/// only part that costs CPU) runs just while someone can see it.
private struct VisibilityReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) { nsView.onChange = onChange }

    final class ReporterView: NSView {
        var onChange: ((Bool) -> Void)?
        private var isVisible = false
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { report(false); return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.evaluate() }
            evaluate()
        }

        private func evaluate() {
            report(window?.occlusionState.contains(.visible) == true && window?.isVisible == true)
        }

        private func report(_ visible: Bool) {
            guard visible != isVisible else { return }
            isVisible = visible
            onChange?(visible)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if isVisible { let cb = onChange; DispatchQueue.main.async { cb?(false) } }
        }
    }
}
