import AudioToolbox
import CoreAudio
import Foundation
import os

private let log = Logger(subsystem: "com.eazyit.AudioDiverger", category: "route")

/// Shared, lock-free gain value read from the real-time IO thread.
final class GainBox: @unchecked Sendable {
    var value: Float
    init(_ value: Float) { self.value = value }
}

/// Redirects the audio of one app to one output device.
///
/// Pipeline:
///   1. A Core Audio *process tap* captures the app's audio and mutes it on
///      its original output (`mutedWhenTapped`).
///   2. A private *aggregate device* combines the tap (as input) with the
///      target output device.
///   3. An IOProc on the aggregate copies tap samples into the output buffers.
final class AppRoute {
    static let aggregatePrefix = "com.eazyit.AudioDiverger.aggregate."

    let appID: String
    let processObjects: [AudioObjectID]
    let deviceUID: String

    private let appName: String
    private let deviceID: AudioObjectID
    private let gain: GainBox
    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(app: AudioApp, device: OutputDevice, volume: Float) {
        appID = app.id
        appName = app.name
        processObjects = app.processObjects
        deviceUID = device.uid
        deviceID = device.id
        gain = GainBox(volume)
    }

    deinit { stop() }

    var volume: Float {
        get { gain.value }
        set { gain.value = max(0, min(newValue, 1)) }
    }

    func start() throws {
        do {
            try createTap()
            try createAggregate()
            try startIO()
            log.info("Route started: \(self.appName, privacy: .public) -> \(self.deviceUID, privacy: .public)")
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
    }

    // MARK: - Steps

    private var tapUUID = UUID()

    private func createTap() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = tapUUID
        description.name = "AudioDiverger – \(appName)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tap = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateProcessTap(description, &tap), "Crearea tap-ului audio")
        tapID = tap
    }

    private func createAggregate() throws {
        let uid = Self.aggregatePrefix + UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioDiverger – \(appName)",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: deviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
        var aggregate = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate),
                    "Crearea dispozitivului agregat")
        aggregateID = aggregate
    }

    private func startIO() throws {
        // The aggregate's input streams = the output device's own inputs
        // (e.g. the AirPods microphone) followed by the tap stream(s).
        // We skip the device inputs and only read the tap.
        let deviceInputStreams = CA.objectIDs(deviceID, kAudioDevicePropertyStreams,
                                              scope: kAudioObjectPropertyScopeInput).count
        let aggregateInputStreams = CA.objectIDs(aggregateID, kAudioDevicePropertyStreams,
                                                 scope: kAudioObjectPropertyScopeInput).count
        let skip = min(deviceInputStreams, max(aggregateInputStreams - 1, 0))
        let gain = self.gain

        var procID: AudioDeviceIOProcID?
        try caCheck(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            Renderer.render(input: input, skipBuffers: skip, output: output, gain: gain.value)
        }, "Crearea IOProc")
        guard let procID else { throw CoreAudioError(status: -1, operation: "Crearea IOProc") }
        ioProcID = procID

        if skip > 0 {
            // Turn the device's microphone streams off so Bluetooth headsets
            // stay in high-quality (A2DP) mode instead of switching to HFP.
            disableInputStreams(procID: procID, total: aggregateInputStreams, disabledPrefix: skip)
        }

        try caCheck(AudioDeviceStart(aggregateID, procID), "Pornirea redării")
    }

    private func disableInputStreams(procID: AudioDeviceIOProcID, total: Int, disabledPrefix: Int) {
        guard total > 0 else { return }
        // struct AudioHardwareIOProcStreamUsage { void* mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
        let header = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let size = header + MemoryLayout<UInt32>.size * total
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(total), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for i in 0..<total {
            raw.storeBytes(of: UInt32(i < disabledPrefix ? 0 : 1),
                           toByteOffset: header + i * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var addr = CA.address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(size), raw)
        if status != noErr {
            log.warning("Could not disable device input streams: \(status)")
        }
    }
}

/// Real-time safe sample copy (no allocations, no locks).
/// HAL IOProcs always see 32-bit float samples.
enum Renderer {
    static func render(input: UnsafePointer<AudioBufferList>,
                       skipBuffers: Int,
                       output: UnsafeMutablePointer<AudioBufferList>,
                       gain: Float) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let first = min(skipBuffers, inList.count)

        var inChannels = 0
        for i in first..<inList.count { inChannels += Int(inList[i].mNumberChannels) }

        var outChannelBase = 0
        for o in 0..<outList.count {
            let buffer = outList[o]
            guard let outData = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let outCh = Int(buffer.mNumberChannels)
            let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outCh)
            let dst = outData.assumingMemoryBound(to: Float.self)
            memset(outData, 0, Int(buffer.mDataByteSize))
            defer { outChannelBase += outCh }
            guard inChannels > 0 else { continue }

            for c in 0..<outCh {
                let global = outChannelBase + c
                // Mono source feeds every output channel; stereo maps L/R 1:1.
                var wanted = inChannels == 1 ? 0 : global
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
                let frames = min(outFrames, inFrames)
                for f in 0..<frames {
                    dst[f * outCh + c] = src[f * inCh + wanted] * gain
                }
            }
        }
    }
}
