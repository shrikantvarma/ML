import Foundation

/// Multi-display SwitchEngine (Approach A — spike-gated PASS on macOS 26.4.1).
/// Resolves a desktop's UUID to its display + managed-space id, asks the
/// WindowServer to make it current via a direct CGS call (no Control+N, so no
/// 9-desktop limit, no Secure-Input/shortcut failure modes), then VERIFIES the
/// landing with a bounded poll — a no-land times out, never hangs, never reports
/// a silent wrong switch.
///
/// All collaborators are injected so every branch is unit-testable without the
/// real WindowServer.
public struct DirectSwitchEngine: SwitchEngine {
    private let spaces: SpacesProvider
    private let switcher: SpaceSwitching
    private let timeoutMs: Int
    private let pollMs: UInt64
    private let now: () -> Date

    public init(
        spaces: SpacesProvider,
        switcher: SpaceSwitching = CGSSpaceSwitcher(),
        timeoutMs: Int = 1500,
        pollMs: UInt64 = 20,
        now: @escaping () -> Date = { Date() }
    ) {
        self.spaces = spaces
        self.switcher = switcher
        self.timeoutMs = timeoutMs
        self.pollMs = pollMs
        self.now = now
    }

    public func `switch`(toSpaceUUID uuid: String) async -> SwitchResult {
        guard let loc = spaces.spaceLocation(uuid: uuid) else { return .driftDetected }
        // Already showing on its display — don't re-issue a switch.
        if spaces.isSpaceCurrent(uuid) { return .switched(latencyMs: 0) }

        let start = now()
        // Private symbol unavailable (renamed/removed on a future OS) → graceful fail.
        guard switcher.setCurrentSpace(displayID: loc.displayID, managedSpaceID: loc.managedSpaceID) else {
            return .verificationFailed
        }

        // Bounded poll. Only the target becoming current on its display counts.
        while now().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            if spaces.isSpaceCurrent(uuid) {
                return .switched(latencyMs: Int(now().timeIntervalSince(start) * 1000))
            }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        return .verificationFailed
    }
}
