import Foundation

/// Read-side seam over the WindowServer. The rest of the app depends only on
/// this protocol; `CGSSpacesProvider` is the v1 implementation and a fake drives
/// tests (plan U3 / KTD-2 / KTD-4).
public protocol SpacesProvider {
    /// Ordered UUIDs of user desktops on the primary display, left → right.
    func orderedUserSpaceUUIDs() -> [String]
    /// UUID of the currently-active desktop, if known.
    func currentSpaceUUID() -> String?
}

public extension SpacesProvider {
    /// 1-based ordinal of `uuid` within the ordered user spaces — the index the
    /// Control+N shortcut targets. nil ⇒ the bound desktop is gone (drift).
    /// KTD-2: resolve at switch time, never cache.
    func resolveIndex(uuid: String) -> Int? {
        guard let i = orderedUserSpaceUUIDs().firstIndex(of: uuid) else { return nil }
        return i + 1
    }
}

/// Production provider backed by the private CGS read-side (proven on macOS 26).
public struct CGSSpacesProvider: SpacesProvider {
    public init() {}
    public func orderedUserSpaceUUIDs() -> [String] {
        CGS.primaryDisplay()?.userSpaces.map { $0.uuid } ?? []
    }
    public func currentSpaceUUID() -> String? {
        CGS.primaryDisplay()?.currentSpaceUUID
    }
}
