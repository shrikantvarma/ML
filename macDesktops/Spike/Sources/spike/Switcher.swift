import Foundation
import CoreGraphics

// The load-bearing mechanism: resolve a stable Space UUID to its current ordinal,
// post Control+number, then VERIFY the landing (KTD-2 / KTD-8). This is exactly
// the logic U4's RealDesktopEngine graduates into.

enum SwitchOutcome: Equatable {
    case switched(latencyMs: Int)
    case driftDetected            // bound UUID absent from the current ordered list
    case notKeyable(index: Int)   // index > 9 → no single Ctrl+number
    case blocked(reason: String)  // Secure Input / shortcut disabled
    case verificationFailed       // posted Ctrl+N but did not land within timeout
}

enum Switcher {
    /// ANSI virtual key codes for digits 1...9 — NON-contiguous; note 5 (0x17)
    /// and 6 (0x16) are out of numeric order. Getting these wrong silently
    /// switches to the wrong desktop, so the spike exercises all of them.
    private static let digitKeyCodes: [CGKeyCode] = [
        0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19,
    ]

    static func currentUUID() -> String? { CGS.primaryDisplay()?.currentSpaceUUID }

    /// 1-based ordinal of `uuid` within the primary display's USER spaces, or nil.
    static func resolveIndex(uuid: String) -> Int? {
        guard let disp = CGS.primaryDisplay() else { return nil }
        guard let idx = disp.userSpaces.firstIndex(where: { $0.uuid == uuid }) else { return nil }
        return idx + 1
    }

    static func postControlNumber(_ n: Int) {
        guard (1...9).contains(n) else { return }
        let key = digitKeyCodes[n - 1]
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = .maskControl
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = .maskControl
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Full flow: resolve → pre-checks → post → BOUNDED verify (never an open
    /// await — a no-event landing must time out, not hang; plan U4).
    static func switchTo(uuid: String, timeoutMs: Int = 1500) -> SwitchOutcome {
        guard let index = resolveIndex(uuid: uuid) else { return .driftDetected }
        guard index <= 9 else { return .notKeyable(index: index) }
        if Probes.secureInputEnabled() { return .blocked(reason: "Secure Input active") }
        if Probes.shortcutEnabled(desktop: index) == false {
            return .blocked(reason: "Switch-to-Desktop \(index) shortcut disabled")
        }

        let start = Date()
        postControlNumber(index)

        let deadline = start.addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            // Guard against misattribution: only an exact match to the expected
            // UUID counts as a landing (a concurrent user switch elsewhere must not).
            if currentUUID() == uuid {
                return .switched(latencyMs: Int(Date().timeIntervalSince(start) * 1000))
            }
            usleep(20_000) // 20ms poll
        }
        return .verificationFailed
    }
}
