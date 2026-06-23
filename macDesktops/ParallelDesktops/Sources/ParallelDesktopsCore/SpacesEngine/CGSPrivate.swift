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
private typealias SetCurrentSpaceFn = @convention(c) (CGSConnectionID, CFString, Int) -> Void

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
    // Multi-display switch (Approach A — spike-gated PASS on macOS 26.4.1).
    private static let getActiveSpace = sym("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let setCurrentSpace = sym("CGSManagedDisplaySetCurrentSpace", as: SetCurrentSpaceFn.self)

    /// Managed id of the globally-active space (the space on the FOCUSED display).
    /// nil if the symbol is unavailable. The spike confirmed this equals a known
    /// `managedSpaceID`, so callers resolve it to a UUID across displays.
    static func activeSpaceID() -> Int? {
        guard let conn = connectionID, let fn = getActiveSpace else { return nil }
        return fn(conn)
    }

    /// Direct-switch `displayID`'s current space to `spaceID` (no Ctrl+N). Returns
    /// false if the symbol is unavailable — caller must verify the landing.
    @discardableResult
    static func directSetCurrentSpace(displayID: String, spaceID: Int64) -> Bool {
        guard let conn = connectionID, let fn = setCurrentSpace else { return false }
        fn(conn, displayID as CFString, Int(spaceID))
        return true
    }

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
}
