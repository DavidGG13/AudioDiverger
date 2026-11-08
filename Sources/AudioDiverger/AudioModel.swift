import AppKit
import Combine
import CoreAudio
import ServiceManagement
import SwiftUI

/// A saved snapshot of every route ("scene"), e.g. "Editing" or "Call".
struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var assignments: [String: [String]]
    var muted: Set<String>
}

@MainActor
final class AudioModel: ObservableObject {
    static let shared = AudioModel()

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var defaultDevice: OutputDevice?
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var assignments: [String: [String]]   // bundle id -> device UIDs
    @Published private(set) var muted: Set<String>
    @Published private(set) var volumes: [String: Float]
    @Published private(set) var presets: [Preset]

    private var deviceNames: [String: String]                      // UID -> last known name
    private var deviceColorSlots: [String: Int]                    // UID -> stable palette slot
    private var routes: [String: AppRoute] = [:]
    private var failedRouteKeys: Set<String> = []
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var visibleSurfaces = 0
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let assignments = "assignments.v2"
        static let legacyAssignments = "assignments"
        static let muted = "muted"
        static let volumes = "volumes"
        static let deviceNames = "deviceNames"
        static let deviceColors = "deviceColors"
        static let presets = "presets"
    }

    private init() {
        Self.migrateLegacyDefaults(defaults)
        if let stored = defaults.dictionary(forKey: Keys.assignments) as? [String: [String]] {
            assignments = stored
        } else {
            let legacy = defaults.dictionary(forKey: Keys.legacyAssignments) as? [String: String] ?? [:]
            assignments = legacy.mapValues { [$0] }
        }
        muted = Set(defaults.stringArray(forKey: Keys.muted) ?? [])
        volumes = (defaults.dictionary(forKey: Keys.volumes) as? [String: Double] ?? [:]).mapValues(Float.init)
        deviceNames = defaults.dictionary(forKey: Keys.deviceNames) as? [String: String] ?? [:]
        deviceColorSlots = defaults.dictionary(forKey: Keys.deviceColors) as? [String: Int] ?? [:]
        presets = (defaults.data(forKey: Keys.presets)).flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []

        // Fully event-driven: no timers. The HAL tells us when processes
        // appear/disappear, devices change, or an app starts/stops playing.
        for selector in [kAudioHardwarePropertyProcessObjectList,
                         kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(.system, &addr, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }

        HotKeyCenter.shared.onPress = { [weak self] index in
            MainActor.assumeIsolated { self?.applyPreset(at: index) }
        }
        HotKeyCenter.shared.install()

        refresh()
    }

    // MARK: - Queries for the UI

    var activeApps: [AudioApp] { apps.filter { $0.isPlaying || hasCustomSetting($0.id) } }
    var inactiveApps: [AudioApp] { apps.filter { !$0.isPlaying && !hasCustomSetting($0.id) } }

    func hasCustomSetting(_ appID: String) -> Bool { assignments[appID] != nil || muted.contains(appID) }

    func assignedUIDs(for appID: String) -> [String] { assignments[appID] ?? [] }

    func isMuted(_ appID: String) -> Bool { muted.contains(appID) }

    func volume(for appID: String) -> Float { volumes[appID] ?? 1 }

    func level(for appID: String) -> Float { routes[appID]?.level.value ?? 0 }

    func deviceName(forUID uid: String) -> String {
        devices.first { $0.uid == uid }?.name ?? deviceNames[uid] ?? "Unknown device"
    }

    func isConnected(uid: String) -> Bool { devices.contains { $0.uid == uid } }

    func color(forUID uid: String?) -> Color {
        guard let uid, let slot = deviceColorSlots[uid] else { return .secondary }
        return DevicePalette.color(slot)
    }

    func isRouted(_ appID: String) -> Bool {
        if case .route = routes[appID]?.kind { return true }
        return false
    }

    var activePresetID: UUID? {
        presets.first { $0.assignments == assignments && $0.muted == muted }?.id
    }

    // MARK: - Actions

    func toggleDevice(_ uid: String, for appID: String) {
        var list = assignments[appID] ?? []
        if let index = list.firstIndex(of: uid) { list.remove(at: index) } else { list.append(uid) }
        setDevices(list, for: appID)
    }

    func setDevices(_ uids: [String], for appID: String) {
        assignments[appID] = uids.isEmpty ? nil : uids
        for uid in uids {
            deviceNames[uid] = deviceName(forUID: uid)
            colorSlot(for: uid)
        }
        persist()
        clearFailure(appID)
        reconcile()
    }

    func toggleMute(_ appID: String) {
        if muted.contains(appID) { muted.remove(appID) } else { muted.insert(appID) }
        routes[appID]?.volume = effectiveGain(appID)
        persist()
        clearFailure(appID)
        reconcile()
    }

    func setVolume(_ value: Float, for appID: String) {
        volumes[appID] = value
        routes[appID]?.volume = effectiveGain(appID)
        defaults.set(volumes.mapValues(Double.init), forKey: Keys.volumes)
    }

    func resetRoutes() {
        assignments.removeAll()
        muted.removeAll()
        errors.removeAll()
        failedRouteKeys.removeAll()
        persist()
        reconcile()
    }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.append(Preset(name: trimmed, assignments: assignments, muted: muted))
        persistPresets()
    }

    func updatePreset(_ id: UUID) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].assignments = assignments
        presets[i].muted = muted
        persistPresets()
    }

    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persistPresets()
    }

    func applyPreset(_ preset: Preset) {
        assignments = preset.assignments
        muted = preset.muted
        errors.removeAll()
        failedRouteKeys.removeAll()
        persist()
        for (appID, route) in routes { route.volume = effectiveGain(appID) }
        reconcile()
    }

    func applyPreset(at index: Int) {
        guard presets.indices.contains(index) else { NSSound.beep(); return }
        applyPreset(presets[index])
    }

    func stopAll() {
        routes.values.forEach { $0.stop() }
        routes.removeAll()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("AudioDiverger: launch at login failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    /// Meters only run while a popover or window is on screen.
    func surfaceVisibilityChanged(_ visible: Bool) {
        visibleSurfaces = max(0, visibleSurfaces + (visible ? 1 : -1))
        reconcile()
    }

    var isMetering: Bool { visibleSurfaces > 0 }

    // MARK: - Persistence

    /// Versions ≤ 1.2.0 used the bundle id "com.eazyit.AudioDiverger".
    /// Copy those settings over once so nobody loses their routes or scenes.
    private static func migrateLegacyDefaults(_ defaults: UserDefaults) {
        let flag = "migratedLegacyDomain"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        guard let legacy = defaults.persistentDomain(forName: "com.eazyit.AudioDiverger") else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    private func persist() {
        defaults.set(assignments, forKey: Keys.assignments)
        defaults.set(Array(muted), forKey: Keys.muted)
        defaults.set(deviceNames, forKey: Keys.deviceNames)
        defaults.set(deviceColorSlots, forKey: Keys.deviceColors)
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: Keys.presets) }
    }

    @discardableResult
    private func colorSlot(for uid: String) -> Int {
        if let slot = deviceColorSlots[uid] { return slot }
        let used = Set(deviceColorSlots.values)
        let slot = (0..<DevicePalette.count).first { !used.contains($0) } ?? deviceColorSlots.count % DevicePalette.count
        deviceColorSlots[uid] = slot
        return slot
    }

    // MARK: - Refresh & routing

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func refresh() {
        let newDevices = DeviceCatalog.outputDevices()
        if newDevices != devices { devices = newDevices }
        for device in newDevices { colorSlot(for: device.uid) }

        let defaultID = DeviceCatalog.defaultOutputDeviceID()
        let newDefault = newDevices.first { $0.id == defaultID }
        if newDefault != defaultDevice { defaultDevice = newDefault }

        let newApps = ProcessCatalog.audioApps()
        if newApps != apps { apps = newApps }

        updateProcessListeners()
        reconcile()
    }

    /// One listener per audio process for "started/stopped playing".
    private func updateProcessListeners() {
        let current = Set(apps.flatMap(\.processObjects))
        for (object, block) in processListeners where !current.contains(object) {
            var addr = CA.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &addr, .main, block)
            processListeners[object] = nil
        }
        for object in current where processListeners[object] == nil {
            var addr = CA.address(kAudioProcessPropertyIsRunningOutput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            if AudioObjectAddPropertyListenerBlock(object, &addr, .main, block) == noErr {
                processListeners[object] = block
            }
        }
    }

    private func effectiveGain(_ appID: String) -> Float {
        muted.contains(appID) ? 0 : volume(for: appID)
    }

    private func desiredKind(for app: AudioApp) -> AppRoute.Kind? {
        let connected = (assignments[app.id] ?? []).filter(isConnected(uid:))
        if !connected.isEmpty { return .route(connected) }
        if muted.contains(app.id) { return .mute }
        if isMetering, app.isPlaying, let uid = defaultDevice?.uid { return .meter(uid) }
        return nil
    }

    private func routeKey(_ app: AudioApp, _ kind: AppRoute.Kind) -> String {
        "\(app.id)|\(kind)|\(app.processObjects.map(String.init).joined(separator: ","))"
    }

    private func clearFailure(_ appID: String) {
        errors[appID] = nil
        failedRouteKeys = failedRouteKeys.filter { !$0.hasPrefix(appID + "|") }
    }

    private func reconcile() {
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        for (appID, route) in routes {
            guard let app = appsByID[appID],
                  let wanted = desiredKind(for: app),
                  wanted == route.kind,
                  app.processObjects == route.processObjects else {
                route.stop()
                routes[appID] = nil
                continue
            }
        }

        for app in apps where routes[app.id] == nil && !app.processObjects.isEmpty {
            guard let kind = desiredKind(for: app) else { continue }
            let key = routeKey(app, kind)
            guard !failedRouteKeys.contains(key) else { continue }

            let uids: [String]
            switch kind {
            case .route(let list): uids = list
            case .meter(let uid): uids = [uid]
            case .mute: uids = []
            }
            let targets = uids.compactMap { uid in devices.first { $0.uid == uid } }
            let gain: Float = { if case .meter = kind { return 1 }; return effectiveGain(app.id) }()
            let route = AppRoute(app: app, kind: kind, devices: targets, volume: gain)
            do {
                try route.start()
                routes[app.id] = route
                errors[app.id] = nil
            } catch {
                failedRouteKeys.insert(key)
                if case .meter = kind { continue }   // metering is best-effort, stay quiet
                errors[app.id] = error.localizedDescription
            }
        }

        for appID in errors.keys where !hasCustomSetting(appID) { errors[appID] = nil }
        objectWillChange.send()
    }
}

/// Stable, theme-adaptive colours for devices. Drawn from the icon's
/// violet→cyan family first.
enum DevicePalette {
    static let colors: [Color] = [
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemCyan),
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemPink),
        Color(nsColor: .systemYellow),
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemMint)
    ]
    static var count: Int { colors.count }
    static func color(_ slot: Int) -> Color { colors[slot % colors.count] }
}
