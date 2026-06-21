import Foundation

// Private SkyLight (WindowServer) symbols — the SINGLE isolation point for
// unsupported APIs (plan KTD-4). Loaded at runtime via dlsym so a renamed/removed
// symbol on a future OS surfaces as a graceful failure, not a link error.
//
// Verified resolving on macOS 26.4.1 by the U1 spike.

typealias CGSConnectionID = Int32

private typealias MainConnFn = @convention(c) () -> CGSConnectionID
private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?

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
}
