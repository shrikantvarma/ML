import AppKit
import Carbon.HIToolbox

/// Minimal global hotkey via Carbon RegisterEventHotKey, isolated to this file.
///
/// Plan note (U11): the plan prefers a Swift-native hotkey lib over Carbon. This
/// is the no-dependency stand-in — RegisterEventHotKey is the one reliable way to
/// *intercept* a global chord (NSEvent global monitors can observe but not consume).
/// Swap for the `KeyboardShortcuts` package during hardening; the call site is the
/// one `init?` below.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private static var instances: [UInt32: GlobalHotKey] = [:]

    /// Returns nil if the chord is already taken (so the caller can surface it — KTD-8).
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, onPress: @escaping () -> Void) {
        self.onPress = onPress

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let pressedID = hkID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.instances[pressedID]?.onPress() }
            }
            return noErr
        }, 1, &spec, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50504453), id: id) // 'PPDS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        GlobalHotKey.instances[id] = self
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}
