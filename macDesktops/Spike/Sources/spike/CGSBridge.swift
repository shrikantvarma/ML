import Foundation

// Private SkyLight (WindowServer) symbols, loaded at RUNTIME via dlsym so the
// spike can REPORT a missing/renamed symbol on a new OS rather than failing to
// link. This is the single isolation point the real app's `SpacesProvider`
// (plan KTD-4) graduates into.

typealias CGSConnectionID = Int32

private typealias MainConnFn = @convention(c) () -> CGSConnectionID
private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> Int
private typealias SetCurrentSpaceFn = @convention(c) (CGSConnectionID, CFString, Int) -> Void

/// One macOS desktop / Space as reported by the WindowServer.
struct SpaceInfo {
    let uuid: String          // stable per-machine identifier (KTD-2 keys on this)
    let managedSpaceID: Int64
    let type: Int             // 0 = user desktop, 4 = fullscreen, etc.
}

/// The ordered set of Spaces on one display.
struct DisplaySpaces {
    let displayIdentifier: String
    let spaces: [SpaceInfo]   // ordered, all types
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

    // Part 2 candidates — probed by the spike, NOT yet used by the app.
    private static let getActiveSpace = sym("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let setCurrentSpace = sym("CGSManagedDisplaySetCurrentSpace", as: SetCurrentSpaceFn.self)

    /// Globally-active space id (the space on the focused display). nil if symbol absent.
    static func activeSpaceID() -> Int? {
        guard let conn = connectionID, let fn = getActiveSpace else { return nil }
        return fn(conn)
    }

    /// Attempt a DIRECT switch (no Ctrl+N) of `displayID`'s current space to `spaceID`.
    /// Returns false if the symbol is unavailable. Landing must be VERIFIED by the caller.
    @discardableResult
    static func directSetCurrentSpace(displayID: String, spaceID: Int64) -> Bool {
        guard let conn = connectionID, let fn = setCurrentSpace else { return false }
        fn(conn, displayID as CFString, Int(spaceID))
        return true
    }

    /// Spike step 1: which private symbols actually resolve on this OS.
    static func diagnostics() -> String {
        var lines: [String] = []
        if handle == nil {
            let err = dlerror().map { String(cString: $0) } ?? "unknown"
            lines.append("SkyLight handle: FAILED — \(err)")
        } else {
            lines.append("SkyLight handle: loaded (\(skylightPath))")
        }
        lines.append("CGSMainConnectionID:          \(mainConn != nil ? "found" : "MISSING")")
        lines.append("CGSCopyManagedDisplaySpaces:  \(copyManaged != nil ? "found" : "MISSING")")
        lines.append("CGSGetActiveSpace:            \(getActiveSpace != nil ? "found" : "MISSING")")
        lines.append("CGSManagedDisplaySetCurrentSpace: \(setCurrentSpace != nil ? "found" : "MISSING")")
        if let cid = connectionID { lines.append("WindowServer connection id:   \(cid)") }
        return lines.joined(separator: "\n")
    }

    static var connectionID: CGSConnectionID? { mainConn?() }

    /// All displays with their ordered Spaces. Returns nil if a symbol is unavailable.
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

    /// Primary display (v1 scope per plan Scope Boundaries / Risk R-4).
    static func primaryDisplay() -> DisplaySpaces? { managedDisplaySpaces()?.first }
}
