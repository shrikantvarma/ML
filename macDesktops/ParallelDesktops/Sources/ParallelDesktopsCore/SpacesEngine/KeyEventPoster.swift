import Foundation
import CoreGraphics

/// Posts the "Switch to Desktop N" shortcut. Behind a protocol so the engine can
/// be tested with a recording fake (no real key events).
public protocol KeyPosting {
    func postControlNumber(_ n: Int)
}

public struct CGEventKeyPoster: KeyPosting {
    public init() {}

    /// ANSI virtual key codes for digits 1...9 — NON-contiguous (note 5/6 swap).
    private static let digitKeyCodes: [CGKeyCode] = [
        0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19,
    ]

    /// Exposed for tests: the key code for a given desktop number (1...9).
    public static func keyCode(forDesktop n: Int) -> CGKeyCode? {
        guard (1...9).contains(n) else { return nil }
        return digitKeyCodes[n - 1]
    }

    public func postControlNumber(_ n: Int) {
        guard let key = Self.keyCode(forDesktop: n) else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = .maskControl
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = .maskControl
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
