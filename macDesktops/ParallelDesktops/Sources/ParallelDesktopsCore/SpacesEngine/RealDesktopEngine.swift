import Foundation

/// v1 SwitchEngine: resolve UUID→ordinal, pre-check failure modes, post Control+N,
/// then VERIFY the landing with a BOUNDED wait (never an open await — a no-event
/// landing must time out, not hang). Plan U4 / KTD-2 / KTD-8.
///
/// All collaborators are injected so every branch is unit-testable without
/// touching the real WindowServer.
public struct RealDesktopEngine: SwitchEngine {
    private let spaces: SpacesProvider
    private let poster: KeyPosting
    private let secureInput: SecureInputChecking
    private let shortcutEnabled: (Int) -> Bool?
    private let timeoutMs: Int
    private let pollMs: UInt64
    private let now: () -> Date

    public init(
        spaces: SpacesProvider,
        poster: KeyPosting = CGEventKeyPoster(),
        secureInput: SecureInputChecking = SystemSecureInput(),
        shortcutEnabled: @escaping (Int) -> Bool? = SymbolicHotkeys.switchToDesktopEnabled,
        timeoutMs: Int = 1500,
        pollMs: UInt64 = 20,
        now: @escaping () -> Date = { Date() }
    ) {
        self.spaces = spaces
        self.poster = poster
        self.secureInput = secureInput
        self.shortcutEnabled = shortcutEnabled
        self.timeoutMs = timeoutMs
        self.pollMs = pollMs
        self.now = now
    }

    public func `switch`(toSpaceUUID uuid: String) async -> SwitchResult {
        // An untrackable target (empty/"?") can never be matched or keyed — treat as drift.
        guard SpaceIdentity.isTrackable(uuid) else { return .driftDetected }
        // B-global: target the GLOBAL Ctrl+N index (position across ALL displays,
        // empties counted), re-derived each switch and never cached (KTD-2).
        guard let index = spaces.globalIndex(uuid: uuid) else { return .driftDetected }
        // Always post the shortcut — no "already current → skip" special-case. macOS
        // does nothing visible if it's already showing (the accepted no-op); verification
        // then sees it current and returns .switched. Keeps the switch path dead simple.
        guard index <= 9 else { return .notKeyable(index: index) }
        if secureInput.isActive() { return .blocked(.secureInput) }
        if shortcutEnabled(index) == false { return .blocked(.shortcutDisabled) }

        let start = now()
        poster.postControlNumber(index)

        // Bounded poll. The desktop is "landed" once it is the current space of any
        // display (focus follows to that screen — expected on multi-display).
        while now().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            if spaces.isSpaceCurrent(uuid: uuid) {
                return .switched(latencyMs: Int(now().timeIntervalSince(start) * 1000))
            }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        // Didn't land. If Secure Input grabbed the keys after our pre-check (TOCTOU),
        // report that specifically rather than a generic verification failure.
        if secureInput.isActive() { return .blocked(.secureInput) }
        return .verificationFailed
    }
}
