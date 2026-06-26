import Foundation
import CoreGraphics

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
    /// User desktops grouped by display, in display order, each ordered left→right
    /// (empties included). Flattening this equals globalDesktopUUIDs().
    func displaysWithDesktops() -> [[String]]
    /// The focused display's current desktop uuid (trackable only; nil otherwise).
    func focusedCurrentSpaceUUID() -> String?
    /// Is `uuid` the current desktop of ANY display? (trackable only)
    func isSpaceCurrent(uuid: String) -> Bool
    /// The set of every display's current desktop uuid (trackable only) — one read,
    /// so callers needing all currents don't issue an IPC per uuid.
    func currentSpaceUUIDs() -> Set<String>
    /// Per-display hardware identifiers, in the same order as `displaysWithDesktops()`.
    /// Used to map displays to friendly `NSScreen` names. Empty when unknown.
    func displayIdentifiers() -> [String]
    /// Make the display that HOSTS `uuid`'s desktop show that desktop — a direct
    /// WindowServer space-set (no Ctrl+N, no focus move). Returns false if unsupported
    /// or unresolvable; the caller must re-read `isSpaceCurrent` to confirm landing.
    /// This is the cross-display lever Ctrl+N can't pull (it only switches the focused
    /// display). Single-display default: false (fakes/single-monitor don't need it).
    func setDisplayCurrentSpace(toSpaceUUID uuid: String) -> Bool
    /// Top-left-origin (Quartz) bounds of the display hosting `uuid`'s desktop, for
    /// placing a window onto that display. nil when unresolvable.
    func displayBounds(forSpaceUUID uuid: String) -> CGRect?
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
    func displaysWithDesktops() -> [[String]] { [orderedUserSpaceUUIDs()] }
    func focusedCurrentSpaceUUID() -> String? { currentSpaceUUID() }
    func isSpaceCurrent(uuid: String) -> Bool { currentSpaceUUID() == uuid }
    func currentSpaceUUIDs() -> Set<String> {
        Set([currentSpaceUUID()].compactMap { $0 }.filter { SpaceIdentity.isTrackable($0) })
    }
    func displayIdentifiers() -> [String] { [] }   // single-display default ⇒ fall back to "Display N"
    func setDisplayCurrentSpace(toSpaceUUID uuid: String) -> Bool { false }
    func displayBounds(forSpaceUUID uuid: String) -> CGRect? { nil }

    /// 1-based ordinal of the display hosting `uuid`'s desktop (Display 1, 2, …).
    /// nil for an untrackable or absent uuid.
    func displayOrdinal(forSpaceUUID uuid: String) -> Int? {
        guard SpaceIdentity.isTrackable(uuid),
              let i = displaysWithDesktops().firstIndex(where: { $0.contains(uuid) }) else { return nil }
        return i + 1
    }

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
    public func globalDesktopUUIDs() -> [String] {
        CGS.allDisplays().flatMap { $0.userSpaces.map { $0.uuid } }   // includes ""/"?"; index needs them
    }
    public func displaysWithDesktops() -> [[String]] {
        CGS.allDisplays().map { $0.userSpaces.map { $0.uuid } }       // flattens to globalDesktopUUIDs()
    }
    public func focusedCurrentSpaceUUID() -> String? {
        CGS.focusedCurrentSpaceUUID().flatMap { SpaceIdentity.isTrackable($0) ? $0 : nil }
    }
    public func isSpaceCurrent(uuid: String) -> Bool {
        guard SpaceIdentity.isTrackable(uuid) else { return false }
        return CGS.allDisplays().contains { $0.currentSpaceUUID == uuid }
    }
    public func currentSpaceUUIDs() -> Set<String> {
        Set(CGS.allDisplays().compactMap { $0.currentSpaceUUID }.filter { SpaceIdentity.isTrackable($0) })
    }
    public func displayIdentifiers() -> [String] {
        CGS.allDisplays().map { $0.displayIdentifier }
    }
    public func setDisplayCurrentSpace(toSpaceUUID uuid: String) -> Bool {
        guard SpaceIdentity.isTrackable(uuid),
              let (displayID, spaceID) = CGS.displayAndSpaceID(forUUID: uuid) else { return false }
        return CGS.directSetCurrentSpace(displayID: displayID, spaceID: spaceID)
    }
    public func displayBounds(forSpaceUUID uuid: String) -> CGRect? {
        guard SpaceIdentity.isTrackable(uuid) else { return nil }
        return CGS.cgBounds(forSpaceUUID: uuid)
    }
}
