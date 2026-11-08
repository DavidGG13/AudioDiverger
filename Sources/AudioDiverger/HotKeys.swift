import Carbon.HIToolbox
import Foundation

/// Global shortcuts ⌃⌥⌘1 … ⌃⌥⌘9 apply presets 1–9.
/// Carbon hot keys need no Accessibility permission and cost nothing when idle.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    static let modifierSymbols = "⌃⌥⌘"

    /// Called on the main thread with the zero-based preset index.
    var onPress: ((Int) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            if status == noErr {
                let index = Int(hotKey.id) - 1
                DispatchQueue.main.async { HotKeyCenter.shared.onPress?(index) }
            }
            return noErr
        }, 1, &spec, nil, nil)

        let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for (index, code) in keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4144_5652), id: UInt32(index + 1)) // 'ADVR'
            if RegisterEventHotKey(UInt32(code), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
            }
        }
    }
}
