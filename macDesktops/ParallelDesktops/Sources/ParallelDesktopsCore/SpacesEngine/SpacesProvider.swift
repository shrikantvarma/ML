import Foundation

/// Where a desktop physically lives: its display + managed-space id. The
/// multi-display direct switch (Approach A) targets a space by these, not by a
/// Control+N ordinal.
public struct SpaceLocation: Equatable {
    public let displayID: String
    public let managedSpaceID: Int64
    public init(displayID: String, managedSpaceID: Int64) {
        self.displayID = displayID
        self.managedSpaceID = managedSpaceID
    }
}

/// Read-side seam over the WindowServer. The rest of the app depends only on
/// this protocol; `CGSSpacesProvider` is the v1 implementation and a fake drives
/// tests (plan U3 / KTD-2 / KTD-4).
public protocol SpacesProvider {
    /// Ordered UUIDs of user desktops on the primary display, left → right.
    func orderedUserSpaceUUIDs() -> [String]
    /// UUID of the desktop on the FOCUSED display (the one you're interacting
    /// with), if known. Multi-display: this is the active space, not just the
    /// primary display's current.
    func currentSpaceUUID() -> String?
    /// Union of user-desktop UUIDs across ALL displays. A desktop moved to a
    /// second screen is still "present" here — so it is NOT drift (multi-display).
    func allUserSpaceUUIDs() -> [String]
    /// Display + managed-space id for `uuid`, across all displays. nil ⇒ the
    /// desktop is on no display (true drift). Drives the direct switch.
    func spaceLocation(uuid: String) -> SpaceLocation?
    /// True if `uuid` is the current (visible) space on its display — i.e. a
    /// switch to it has landed. Verification signal for the direct switch.
    func isSpaceCurrent(_ uuid: String) -> Bool
}

public extension SpacesProvider {
    /// Default: single-display behaviour. `CGSSpacesProvider` overrides with the
    /// real cross-display union; existing single-display fakes inherit this.
    func allUserSpaceUUIDs() -> [String] { orderedUserSpaceUUIDs() }

    /// Default: single-display — "current" is the one active space.
    func isSpaceCurrent(_ uuid: String) -> Bool { currentSpaceUUID() == uuid }

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
    /// Focused-display current: resolve the globally-active space id to its UUID
    /// across all displays; fall back to the primary display's current if the
    /// active-space symbol is unavailable. Fixes recalibrate/current binding to
    /// the wrong screen on multi-display.
    public func currentSpaceUUID() -> String? {
        if let active = CGS.activeSpaceID() {
            for d in CGS.allDisplays() {
                if let s = d.spaces.first(where: { Int($0.managedSpaceID) == active }) { return s.uuid }
            }
        }
        return CGS.primaryDisplay()?.currentSpaceUUID
    }
    public func allUserSpaceUUIDs() -> [String] {
        CGS.allDisplays().flatMap { $0.userSpaces.map { $0.uuid } }
    }
    public func spaceLocation(uuid: String) -> SpaceLocation? {
        for d in CGS.allDisplays() {
            if let s = d.userSpaces.first(where: { $0.uuid == uuid }) {
                return SpaceLocation(displayID: d.displayIdentifier, managedSpaceID: s.managedSpaceID)
            }
        }
        return nil
    }
    public func isSpaceCurrent(_ uuid: String) -> Bool {
        CGS.allDisplays().contains { $0.currentSpaceUUID == uuid }
    }
}

/// Write-side seam for the direct space switch (Approach A). Behind a protocol so
/// the engine is unit-testable without touching the WindowServer.
public protocol SpaceSwitching {
    /// Make `managedSpaceID` the current space on `displayID`. Returns false if
    /// the private symbol is unavailable (graceful degradation).
    func setCurrentSpace(displayID: String, managedSpaceID: Int64) -> Bool
}

public struct CGSSpaceSwitcher: SpaceSwitching {
    public init() {}
    public func setCurrentSpace(displayID: String, managedSpaceID: Int64) -> Bool {
        CGS.directSetCurrentSpace(displayID: displayID, spaceID: managedSpaceID)
    }
}
