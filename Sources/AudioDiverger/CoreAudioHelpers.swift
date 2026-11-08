import CoreAudio
import Foundation

/// Error thrown when a Core Audio call fails.
struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? {
        "\(operation) a eșuat (cod \(status)\(fourCC))"
    }

    private var fourCC: String {
        let n = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((n >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }),
              let s = String(bytes: bytes, encoding: .ascii) else { return "" }
        return ", '\(s)'"
    }
}

@inline(__always)
func caCheck(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    if status != noErr { throw CoreAudioError(status: status, operation: operation()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}

/// Thin, typed wrappers around the AudioObject property API.
enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func scalar<T>(_ object: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          initial: T) -> T? {
        var addr = address(selector, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID,
                       _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var addr = address(selector, scope)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    static func objectIDs(_ object: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Total number of channels a device exposes in the given scope.
    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
