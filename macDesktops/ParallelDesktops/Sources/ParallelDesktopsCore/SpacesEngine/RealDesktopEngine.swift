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
        guard let index = spaces.resolveIndex(uuid: uuid) else { return .driftDetected }
        guard index <= 9 else { return .notKeyable(index: index) }
        if secureInput.isActive() { return .blocked(.secureInput) }
        if shortcutEnabled(index) == false { return .blocked(.shortcutDisabled) }

        let start = now()
        poster.postControlNumber(index)

        // Bounded poll. Only an exact match to the expected UUID counts as a
        // landing — a concurrent user switch elsewhere must not be misread.
        while now().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            if spaces.currentSpaceUUID() == uuid {
                return .switched(latencyMs: Int(now().timeIntervalSince(start) * 1000))
            }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        return .verificationFailed
    }
}
