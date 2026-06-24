import Foundation

// Private SkyLight (WindowServer) symbols — the SINGLE isolation point for
// unsupported APIs (plan KTD-4). Loaded at runtime via dlsym so a renamed/removed
// symbol on a future OS surfaces as a graceful failure, not a link error.
//
// Verified resolving on macOS 26.4.1 by the U1 spike.

typealias CGSConnectionID = Int32

private typealias MainConnFn = @convention(c) () -> CGSConnectionID
private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> Int

struct SpaceInfo {
    let uuid: String
    let managedSpaceID: Int64
    let type: Int          // 0 = user desktop, 4 = fullscreen, etc.
}

struct DisplaySpaces {
    let displayIdentifier: String
    let spaces: [SpaceInfo]
    let currentSpaceUUID: String?
    var userSpaces: [SpaceInfo] { spaces.filter { $0.type == 0 } }
}

enum CGS {
    static let skylightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let handle: UnsafeMutableRawPointer? = dlopen(skylightPath, RTLD_LAZY)

    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let h = handle, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let mainConn = sym("CGSMainConnectionID", as: MainConnFn.self)
    private static let copyManaged = sym("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self)
    private static let getActiveSpace = sym("CGSGetActiveSpace", as: GetActiveSpaceFn.self)

    static var symbolsAvailable: Bool { mainConn != nil && copyManaged != nil }
    static var connectionID: CGSConnectionID? { mainConn?() }

    static func managedDisplaySpaces() -> [DisplaySpaces]? {
        guard let conn = connectionID, let copy = copyManaged else { return nil }
        guard let arr = copy(conn)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return arr.map { displayDict in
            let displayID = displayDict["Display Identifier"] as? String ?? "?"
            let spacesArr = displayDict["Spaces"] as? [[String: Any]] ?? []
            let spaces: [SpaceInfo] = spacesArr.map { s in
                let uuid = s["uuid"] as? String ?? "?"
                let mid = (s["ManagedSpaceID"] as? NSNumber)?.int64Value
                    ?? (s["id64"] as? NSNumber)?.int64Value ?? -1
                let type = (s["type"] as? NSNumber)?.intValue ?? -1
                return SpaceInfo(uuid: uuid, managedSpaceID: mid, type: type)
            }
            let current = (displayDict["Current Space"] as? [String: Any])?["uuid"] as? String
            return DisplaySpaces(displayIdentifier: displayID, spaces: spaces, currentSpaceUUID: current)
        }
    }

    /// Primary display only (v1 scope per plan Risk R-4).
    static func primaryDisplay() -> DisplaySpaces? { managedDisplaySpaces()?.first }

    /// All displays with their ordered Spaces (empty if a symbol is unavailable).
    static func allDisplays() -> [DisplaySpaces] { managedDisplaySpaces() ?? [] }

    /// Globally-active space id (focused display). nil if symbol absent.
    static func activeSpaceID() -> Int? {
        guard let conn = connectionID, let fn = getActiveSpace else { return nil }
        return fn(conn)
    }

    /// Focused display's current space uuid (via CGSGetActiveSpace → managedSpaceID
    /// match). Falls back to the primary display's current if the symbol is missing
    /// or the active id matches no space. Returns nil if the resulting desktop is
    /// untrackable (empty/"?") — the contract callers (e.g. recomputeCurrent) rely on.
    static func focusedCurrentSpaceUUID() -> String? {
        guard let active = activeSpaceID() else { return primaryFocusFallback() }
        for d in allDisplays() {
            // managedSpaceID == -1 is the parse-failure sentinel — never let it alias `active`.
            for s in d.spaces where s.managedSpaceID >= 0 && Int(s.managedSpaceID) == active {
                return SpaceIdentity.isTrackable(s.uuid) ? s.uuid : nil
            }
        }
        return primaryFocusFallback()
    }

    /// Symbol-missing / no-match fallback. The "nil when untrackable" guard lives
    /// here so an empty/"?" sentinel can never escape on the fallback paths.
    private static func primaryFocusFallback() -> String? {
        primaryDisplay()?.currentSpaceUUID.flatMap { SpaceIdentity.isTrackable($0) ? $0 : nil }
    }
}
