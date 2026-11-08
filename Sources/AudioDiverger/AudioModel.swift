import AppKit
import Combine
import CoreAudio
import ServiceManagement

@MainActor
final class AudioModel: ObservableObject {
    static let shared = AudioModel()

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var defaultDeviceName = "—"
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var assignments: [String: String]      // bundle id -> device UID
    @Published private(set) var volumes: [String: Float]
    @Published var onlyActive: Bool {
        didSet { defaults.set(onlyActive, forKey: Keys.onlyActive) }
    }

    private var deviceNames: [String: String]                       // device UID -> last known name
    private var routes: [String: AppRoute] = [:]
    private var failedRouteKeys: Set<String> = []
    private var pendingRefresh: DispatchWorkItem?
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let assignments = "assignments"
        static let volumes = "volumes"
        static let deviceNames = "deviceNames"
        static let onlyActive = "onlyActive"
    }

    private init() {
        assignments = defaults.dictionary(forKey: Keys.assignments) as? [String: String] ?? [:]
        volumes = (defaults.dictionary(forKey: Keys.volumes) as? [String: Double] ?? [:]).mapValues(Float.init)
        deviceNames = defaults.dictionary(forKey: Keys.deviceNames) as? [String: String] ?? [:]
        onlyActive = defaults.object(forKey: Keys.onlyActive) as? Bool ?? false

        for selector in [kAudioHardwarePropertyProcessObjectList,
                         kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice] {
            listen(selector)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        // "Is playing" flags change without a list change; poll them gently.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    // MARK: - Public API for the UI

    var visibleApps: [AudioApp] {
        guard onlyActive else { return apps }
        return apps.filter { $0.isPlaying || assignments[$0.id] != nil }
    }

    func assignedDeviceUID(for appID: String) -> String { assignments[appID] ?? "" }

    func deviceName(forUID uid: String) -> String {
        devices.first { $0.uid == uid }?.name ?? deviceNames[uid] ?? "Dispozitiv necunoscut"
    }

    func isConnected(uid: String) -> Bool { devices.contains { $0.uid == uid } }

    func isRouted(_ appID: String) -> Bool { routes[appID] != nil }

    func volume(for appID: String) -> Float { volumes[appID] ?? 1 }

    func setDevice(_ uid: String, for appID: String) {
        if uid.isEmpty {
            assignments[appID] = nil
        } else {
            assignments[appID] = uid
            deviceNames[uid] = deviceName(forUID: uid)
            defaults.set(deviceNames, forKey: Keys.deviceNames)
        }
        defaults.set(assignments, forKey: Keys.assignments)
        errors[appID] = nil
        failedRouteKeys = failedRouteKeys.filter { !$0.hasPrefix(appID + "|") }
        reconcile()
    }

    func setVolume(_ value: Float, for appID: String) {
        volumes[appID] = value
        routes[appID]?.volume = value
        defaults.set(volumes.mapValues(Double.init), forKey: Keys.volumes)
    }

    func resetAll() {
        assignments.removeAll()
        defaults.set(assignments, forKey: Keys.assignments)
        errors.removeAll()
        failedRouteKeys.removeAll()
        reconcile()
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

    // MARK: - Refresh & routing

    private func listen(_ selector: AudioObjectPropertySelector) {
        var addr = CA.address(selector)
        AudioObjectAddPropertyListenerBlock(.system, &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    /// Coalesces bursts of HAL notifications into a single refresh.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func refresh() {
        let newDevices = DeviceCatalog.outputDevices()
        if newDevices != devices { devices = newDevices }

        let defaultID = DeviceCatalog.defaultOutputDeviceID()
        let name = newDevices.first { $0.id == defaultID }?.name ?? "—"
        if name != defaultDeviceName { defaultDeviceName = name }

        let newApps = ProcessCatalog.audioApps()
        if newApps != apps { apps = newApps }

        reconcile()
    }

    private func routeKey(_ app: AudioApp, _ uid: String) -> String {
        "\(app.id)|\(uid)|\(app.processObjects.map(String.init).joined(separator: ","))"
    }

    private func reconcile() {
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        // Tear down routes that are no longer valid.
        for (appID, route) in routes {
            let app = appsByID[appID]
            let wanted = assignments[appID]
            let stillValid = app != nil
                && wanted == route.deviceUID
                && isConnected(uid: route.deviceUID)
                && app!.processObjects == route.processObjects
            if !stillValid {
                route.stop()
                routes[appID] = nil
            }
        }

        // Create the routes that are missing.
        for app in apps {
            guard routes[app.id] == nil,
                  let uid = assignments[app.id],
                  let device = devices.first(where: { $0.uid == uid }),
                  !app.processObjects.isEmpty else { continue }

            let key = routeKey(app, uid)
            guard !failedRouteKeys.contains(key) else { continue }

            let route = AppRoute(app: app, device: device, volume: volume(for: app.id))
            do {
                try route.start()
                routes[app.id] = route
                errors[app.id] = nil
            } catch {
                failedRouteKeys.insert(key)
                errors[app.id] = error.localizedDescription
            }
        }

        // Clear stale errors for apps that are no longer assigned.
        for appID in errors.keys where assignments[appID] == nil { errors[appID] = nil }
    }
}
