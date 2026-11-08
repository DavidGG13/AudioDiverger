import AudioToolbox
import CoreAudio
import Foundation
import os

private let log = Logger(subsystem: "com.easyinfotech.AudioDiverger", category: "route")

/// Plain values shared with the real-time IO thread. Aligned 32-bit
/// loads/stores are atomic on Apple silicon and Intel, which is all we need
/// for a gain and a meter level.
final class SharedFloat: @unchecked Sendable {
    var value: Float
    init(_ value: Float) { self.value = value }
}

/// Taps one app's audio and does one of three things with it:
/// - `.route`: mutes it on its original output and plays it on 1+ devices;
/// - `.mute`: mutes it, no IO at all (cheapest);
/// - `.meter`: leaves it untouched and only measures its level (used only
///   while the UI is visible).
final class AppRoute {
    enum Kind: Equatable {
        case route([String])     // device UIDs, first is the clock
        case mute
        case meter(String)       // clock device UID (system default)
    }

    static let aggregatePrefix = "com.easyinfotech.AudioDiverger.aggregate."

    let appID: String
    let processObjects: [AudioObjectID]
    let kind: Kind

    /// Smoothed peak level 0…1, written by the IO thread.
    let level = SharedFloat(0)

    private let appName: String
    private let devices: [OutputDevice]
    private let gain: SharedFloat
    private let tapUUID = UUID()
    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(app: AudioApp, kind: Kind, devices: [OutputDevice], volume: Float) {
        appID = app.id
        appName = app.name
        processObjects = app.processObjects
        self.kind = kind
        self.devices = devices
        gain = SharedFloat(volume)
    }

    deinit { stop() }

    var volume: Float {
        get { gain.value }
        set { gain.value = max(0, min(newValue, 1)) }
    }

    func start() throws {
        do {
            try createTap()
            if kind != .mute {
                try createAggregate()
                try startIO()
            }
            log.info("Started \(String(describing: self.kind), privacy: .public) for \(self.appName, privacy: .public)")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != .unknown, let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
        level.value = 0
    }

    // MARK: - Steps

    private func createTap() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = tapUUID
        description.name = "AudioDiverger – \(appName)"
        description.isPrivate = true
        switch kind {
        case .route: description.muteBehavior = .mutedWhenTapped
        case .mute: description.muteBehavior = .muted
        case .meter: description.muteBehavior = .unmuted
        }
        var tap = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateProcessTap(description, &tap), "Creating the audio tap")
        tapID = tap
    }

    private func createAggregate() throws {
        guard let main = devices.first else {
            throw CoreAudioError(status: -1, operation: "Choosing the output device")
        }
        let subDevices: [[String: Any]] = devices.enumerated().map { index, device in
            [kAudioSubDeviceUIDKey: device.uid,
             kAudioSubDeviceDriftCompensationKey: index > 0]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioDiverger – \(appName)",
            kAudioAggregateDeviceUIDKey: Self.aggregatePrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: main.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString,
                 kAudioSubTapDriftCompensationKey: true]
            ]
        ]
        var aggregate = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate),
                    "Creating the aggregate device")
        aggregateID = aggregate
    }

    private func streamCount(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        CA.objectIDs(device, kAudioDevicePropertyStreams, scope: scope).count
    }

    private func startIO() throws {
        // Aggregate input streams = every sub-device's own inputs (e.g. an
        // AirPods mic), in sub-device order, followed by the tap stream.
        let deviceInputs = devices.reduce(0) { $0 + streamCount($1.id, kAudioObjectPropertyScopeInput) }
        let aggregateInputs = streamCount(aggregateID, kAudioObjectPropertyScopeInput)
        let skip = min(deviceInputs, max(aggregateInputs - 1, 0))

        // Aggregate output streams are grouped per sub-device, in order.
        var groups: [Renderer.Group] = []
        if case .route = kind {
            var first = 0
            for device in devices {
                let count = streamCount(device.id, kAudioObjectPropertyScopeOutput)
                groups.append(.init(firstBuffer: first, bufferCount: count))
                first += count
            }
        }
        let plan = Renderer.Plan(skipInputBuffers: skip, outputGroups: groups)
        let gain = self.gain
        let level = self.level

        var procID: AudioDeviceIOProcID?
        try caCheck(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            Renderer.render(input: input, output: output, plan: plan, gain: gain.value, level: level)
        }, "Creating the IOProc")
        guard let procID else { throw CoreAudioError(status: -1, operation: "Creating the IOProc") }
        ioProcID = procID

        if skip > 0 {
            // Keep Bluetooth headsets in high-quality (A2DP) mode by turning
            // their microphone streams off for our IOProc.
            setInputStreamUsage(procID: procID, total: aggregateInputs, disabledPrefix: skip)
        }

        try caCheck(AudioDeviceStart(aggregateID, procID), "Starting playback")
    }

    private func setInputStreamUsage(procID: AudioDeviceIOProcID, total: Int, disabledPrefix: Int) {
        guard total > 0 else { return }
        // struct AudioHardwareIOProcStreamUsage { void* mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
        let pointerSize = MemoryLayout<UnsafeMutableRawPointer>.size
        let header = pointerSize + MemoryLayout<UInt32>.size
        let size = header + MemoryLayout<UInt32>.size * total
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(total), toByteOffset: pointerSize, as: UInt32.self)
        for i in 0..<total {
            raw.storeBytes(of: UInt32(i < disabledPrefix ? 0 : 1),
                           toByteOffset: header + i * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var addr = CA.address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(size), raw)
        if status != noErr { log.warning("Could not disable device input streams: \(status)") }
    }
}

/// Real-time safe sample copy (no allocations, no locks).
/// HAL IOProcs always see 32-bit float samples.
enum Renderer {
    struct Group { let firstBuffer: Int; let bufferCount: Int }
    struct Plan { let skipInputBuffers: Int; let outputGroups: [Group] }

    static func render(input: UnsafePointer<AudioBufferList>,
                       output: UnsafeMutablePointer<AudioBufferList>,
                       plan: Plan,
                       gain: Float,
                       level: SharedFloat) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let first = min(plan.skipInputBuffers, inList.count)

        // Silence everything we own first; groups below fill their channels.
        for buffer in outList where buffer.mData != nil {
            memset(buffer.mData!, 0, Int(buffer.mDataByteSize))
        }

        // Meter: smoothed peak of the tapped signal (pre-gain).
        var peak: Float = 0
        var inChannels = 0
        for i in first..<inList.count {
            let b = inList[i]
            inChannels += Int(b.mNumberChannels)
            guard let data = b.mData else { continue }
            let samples = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let p = data.assumingMemoryBound(to: Float.self)
            for s in 0..<samples { peak = max(peak, abs(p[s])) }
        }
        level.value = max(min(peak * gain, 1), level.value * 0.85)

        guard inChannels > 0, gain > 0 else { return }

        for group in plan.outputGroups {
            var channelBase = 0
            let end = min(group.firstBuffer + group.bufferCount, outList.count)
            guard group.firstBuffer < end else { continue }
            for o in group.firstBuffer..<end {
                let buffer = outList[o]
                guard let outData = buffer.mData, buffer.mNumberChannels > 0 else { continue }
                let outCh = Int(buffer.mNumberChannels)
                let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outCh)
                let dst = outData.assumingMemoryBound(to: Float.self)
                defer { channelBase += outCh }

                for c in 0..<outCh {
                    // Stereo maps L/R onto this device's first two channels;
                    // a mono source feeds both.
                    var wanted = inChannels == 1 ? 0 : channelBase + c
                    guard wanted < inChannels else { continue }
                    var b = first
                    while b < inList.count, wanted >= Int(inList[b].mNumberChannels) {
                        wanted -= Int(inList[b].mNumberChannels)
                        b += 1
                    }
                    guard b < inList.count, let inData = inList[b].mData else { continue }
                    let inCh = Int(inList[b].mNumberChannels)
                    let inFrames = Int(inList[b].mDataByteSize) / (MemoryLayout<Float>.size * inCh)
                    let src = inData.assumingMemoryBound(to: Float.self)
                    for f in 0..<min(outFrames, inFrames) {
                        dst[f * outCh + c] = src[f * inCh + wanted] * gain
                    }
                }
            }
        }
    }
}
