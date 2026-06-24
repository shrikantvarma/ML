import Foundation

/// Identity guard for Space UUIDs. macOS returns `uuid: ""` for some real
/// desktops, and the CGS parser maps a missing key to `"?"`; binding, matching,
/// or returning either sentinel would collide across every such desktop. A
/// non-trackable uuid must NEVER be bound, matched, returned, or treated as
/// "current" (B-global empty-UUID guard).
public enum SpaceIdentity {
    public static func isTrackable(_ uuid: String) -> Bool { !uuid.isEmpty && uuid != "?" }
}

/// Read-side seam over the WindowServer. The rest of the app depends only on
/// this protocol; `CGSSpacesProvider` is the v1 implementation and a fake drives
/// tests (plan U3 / KTD-2 / KTD-4). The multi-display methods carry single-display
/// defaults so existing fakes and single-monitor behavior are unchanged.
public protocol SpacesProvider {
    /// Ordered UUIDs of user desktops on the primary display, left → right.
    func orderedUserSpaceUUIDs() -> [String]
    /// UUID of the currently-active desktop, if known.
    func currentSpaceUUID() -> String?
    /// Ordered UUIDs of ALL user desktops across every display — INCLUDING
    /// empty-uuid desktops, because macOS numbers them for Ctrl+N. This is the
    /// global-index list; do not filter it.
    func globalDesktopUUIDs() -> [String]
    /// The focused display's current desktop uuid (trackable only; nil otherwise).
    func focusedCurrentSpaceUUID() -> String?
    /// Is `uuid` the current desktop of ANY display? (trackable only)
    func isSpaceCurrent(uuid: String) -> Bool
}

public extension SpacesProvider {
    /// 1-based ordinal of `uuid` within the ordered user spaces — the index the
    /// Control+N shortcut targets. nil ⇒ the bound desktop is gone (drift).
    /// KTD-2: resolve at switch time, never cache.
    func resolveIndex(uuid: String) -> Int? {
        guard let i = orderedUserSpaceUUIDs().firstIndex(of: uuid) else { return nil }
        return i + 1
    }

    // Single-display defaults: one display ⇒ the global list IS the primary list,
    // the focused current IS the primary current. Existing fakes keep working.
    func globalDesktopUUIDs() -> [String] { orderedUserSpaceUUIDs() }
    func focusedCurrentSpaceUUID() -> String? { currentSpaceUUID() }
    func isSpaceCurrent(uuid: String) -> Bool { currentSpaceUUID() == uuid }

    /// Trackable user desktops across all displays — the "present" set for drift.
    /// Excludes empties (they can't host a Project), unlike `globalDesktopUUIDs()`.
    func allTrackableUserSpaceUUIDs() -> [String] {
        globalDesktopUUIDs().filter { SpaceIdentity.isTrackable($0) }
    }

    /// 1-based Ctrl+N index = position in the FULL ordered list (empties counted,
    /// because macOS numbers them). nil for an untrackable or absent uuid.
    func globalIndex(uuid: String) -> Int? {
        guard SpaceIdentity.isTrackable(uuid),
              let i = globalDesktopUUIDs().firstIndex(of: uuid) else { return nil }
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
