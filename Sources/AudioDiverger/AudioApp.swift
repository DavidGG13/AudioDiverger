import AppKit
import CoreAudio
import Darwin

/// A user-facing application, grouping every audio process that belongs to it
/// (e.g. Chrome/Safari play audio from helper processes, not the main one).
struct AudioApp: Identifiable, Equatable {
    let id: String          // bundle identifier
    let name: String
    let icon: NSImage
    var processObjects: [AudioObjectID]
    var isPlaying: Bool

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name &&
        lhs.processObjects == rhs.processObjects && lhs.isPlaying == rhs.isPlaying
    }
}

enum ProcessCatalog {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    /// Private but long-standing libsystem function: maps a helper/XPC process
    /// to the app that is "responsible" for it.
    private static let responsibleFn: ResponsibleFn? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        if let fn = responsibleFn {
            let r = fn(pid)
            if r > 0 { return r }
        }
        return pid
    }

    private static func isUserApp(_ app: NSRunningApplication?) -> Bool {
        guard let app, app.bundleIdentifier != nil else { return false }
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    private static func owningApp(pid: pid_t, bundleID: String, running: [NSRunningApplication]) -> NSRunningApplication? {
        let responsible = NSRunningApplication(processIdentifier: responsiblePID(for: pid))
        if isUserApp(responsible) { return responsible }
        let own = NSRunningApplication(processIdentifier: pid)
        if isUserApp(own) { return own }
        // Fallback: helpers usually carry the parent's bundle id as a prefix.
        guard !bundleID.isEmpty else { return nil }
        return running.first { app in
            guard isUserApp(app), let parent = app.bundleIdentifier else { return false }
            return bundleID.hasPrefix(parent + ".")
        }
    }

    static func audioApps() -> [AudioApp] {
        let me = getpid()
        let running = NSWorkspace.shared.runningApplications
        var groups: [String: AudioApp] = [:]

        for object in CA.objectIDs(.system, kAudioHardwarePropertyProcessObjectList) {
            guard let pid = CA.scalar(object, kAudioProcessPropertyPID, initial: pid_t(-1)),
                  pid > 0, pid != me else { continue }
            let bundleID = CA.string(object, kAudioProcessPropertyBundleID) ?? ""
            guard let app = owningApp(pid: pid, bundleID: bundleID, running: running),
                  app.processIdentifier != me,
                  let key = app.bundleIdentifier else { continue }

            let playing = (CA.scalar(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0
            var entry = groups[key] ?? AudioApp(id: key,
                                                name: app.localizedName ?? key,
                                                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                                                processObjects: [],
                                                isPlaying: false)
            entry.processObjects.append(object)
            entry.isPlaying = entry.isPlaying || playing
            groups[key] = entry
        }

        return groups.values
            .map { var a = $0; a.processObjects.sort(); return a }
            .sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
    }
}
