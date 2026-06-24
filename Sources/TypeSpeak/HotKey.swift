import Carbon.HIToolbox
import AppKit

/// Global system-wide hotkey via Carbon RegisterEventHotKey.
/// Works without Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let callback: () -> Void
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    /// keyCode: virtual key (e.g. kVK_Space = 49). modifiers: Carbon flags (e.g. optionKey).
    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        self.id = HotKey.nextID
        HotKey.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        // Carbon dispatches this on the main run loop.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            MainActor.assumeIsolated {
                HotKey.instances[hkID.id]?.callback()
            }
            return noErr
        }, 1, &eventType, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x54534B59 /* 'TSKY' */), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.instances[id] = self
    }

    // No deinit: the app holds a single hotkey for its whole lifetime.
}
