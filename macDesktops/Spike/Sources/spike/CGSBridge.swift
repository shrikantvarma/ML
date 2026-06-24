import Foundation
import Carbon   // ProcessSerialNumber / GetProcessForPID (for the SLPS nudge)

// Private SkyLight (WindowServer) symbols, loaded at RUNTIME via dlsym so the
// spike can REPORT a missing/renamed symbol on a new OS rather than failing to
// link. This is the single isolation point the real app's `SpacesProvider`
// (plan KTD-4) graduates into.

typealias CGSConnectionID = Int32

private typealias MainConnFn = @convention(c) () -> CGSConnectionID
private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> Int
private typealias SetCurrentSpaceFn = @convention(c) (CGSConnectionID, CFString, Int) -> Void
// SkyLight Process Server (SLPS) — the no-SIP activation family yabai uses to make a
// window front/key WITHOUT raising. This is what a real menu-bar click does under the hood.
private typealias SetFrontProcessFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
private typealias PostEventRecordToFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> Int32

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

/// A Space's durable identity guard. macOS reports an empty `uuid` ("") for some
/// genuine user desktops (seen for ones dragged between monitors), and this bridge's
/// parser maps a MISSING key to "?". Binding to / matching either sentinel collides
/// across every such desktop — so NEVER bind, match, or return a non-trackable uuid.
/// This is the exact predicate the real app's identity layer must graduate into.
enum SpaceIdentity {
    static func isTrackable(_ uuid: String) -> Bool { !uuid.isEmpty && uuid != "?" }
}

/// One private symbol resolved at runtime, recording WHICH candidate name matched.
struct ResolvedSym<T> {
    let fn: T?
    let name: String?   // the candidate name that resolved (for diagnostics), nil if none
    var found: Bool { fn != nil }
}

enum CGS {
    static let skylightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let handle: UnsafeMutableRawPointer? = dlopen(skylightPath, RTLD_LAZY)

    /// Resolve the FIRST candidate name that exists. We list the SkyLight `SLS*` name
    /// before the legacy `CGS*` mirror: the symbols exist in both namespaces and
    /// SkyLight is the more future-proof one (Hammerspoon migrated to SLS* for exactly
    /// this reason). Behavior-identical mirrors; this hedges a future CGS->SLS rename
    /// at zero cost, and validates the exact resolution path the shipping app will use.
    private static func sym2<T>(_ names: [String], as type: T.Type) -> ResolvedSym<T> {
        guard let h = handle else { return ResolvedSym(fn: nil, name: nil) }
        for n in names {
            if let p = dlsym(h, n) { return ResolvedSym(fn: unsafeBitCast(p, to: T.self), name: n) }
        }
        return ResolvedSym(fn: nil, name: nil)
    }

    private static let mainConnR = sym2(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnFn.self)
    private static let copyManagedR = sym2(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: CopyManagedDisplaySpacesFn.self)
    // Part 2 candidates — probed by the spike, NOT yet used by the app.
    private static let getActiveSpaceR = sym2(["SLSGetActiveSpace", "CGSGetActiveSpace"], as: GetActiveSpaceFn.self)
    private static let setCurrentSpaceR = sym2(["SLSManagedDisplaySetCurrentSpace", "CGSManagedDisplaySetCurrentSpace"], as: SetCurrentSpaceFn.self)

    private static var mainConn: MainConnFn? { mainConnR.fn }
    private static var copyManaged: CopyManagedDisplaySpacesFn? { copyManagedR.fn }
    private static var getActiveSpace: GetActiveSpaceFn? { getActiveSpaceR.fn }
    private static var setCurrentSpace: SetCurrentSpaceFn? { setCurrentSpaceR.fn }

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

    fileprivate static let setFrontProcessR = sym2(["_SLPSSetFrontProcessWithOptions"], as: SetFrontProcessFn.self)
    fileprivate static let postEventRecordR = sym2(["SLPSPostEventRecordTo"], as: PostEventRecordToFn.self)

    // GetProcessForPID is unavailable to the Swift importer (deprecated pre-10.9) but
    // the runtime symbol still exists in CoreServices, so resolve it via dlsym too.
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private static let getProcessForPID: GetProcessForPIDFn? = {
        guard let p = dlsym(dlopen(nil, RTLD_LAZY), "GetProcessForPID") else { return nil }
        return unsafeBitCast(p, to: GetProcessForPIDFn.self)
    }()

    /// Force the WindowServer's process server to make `pid`'s window front+key — the
    /// no-SIP activation a menu-bar click performs (yabai technique). Mitigation probe
    /// for the stale menu bar a bare space switch leaves. Returns false if symbols absent.
    @discardableResult
    static func frontProcessNudge(pid: pid_t, windowID: UInt32) -> Bool {
        guard let setFront = setFrontProcessR.fn, let getPSN = getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        let kCPSUserGenerated: UInt32 = 0x200
        _ = setFront(&psn, windowID, kCPSUserGenerated)
        // Make it the key window via two synthetic activation event records.
        if let post = postEventRecordR.fn {
            var b1 = [UInt8](repeating: 0, count: 0xf8)
            var b2 = [UInt8](repeating: 0, count: 0xf8)
            b1[0x04] = 0xf8; b1[0x08] = 0x01; b1[0x3a] = 0x10
            b2[0x04] = 0xf8; b2[0x08] = 0x02; b2[0x3a] = 0x10
            withUnsafeBytes(of: windowID) { wb in
                for i in 0..<4 { b1[0x3c + i] = wb[i]; b2[0x3c + i] = wb[i] }
            }
            for i in 0..<0x10 { b1[0x20 + i] = 0xFF; b2[0x20 + i] = 0xFF }
            b1.withUnsafeBufferPointer { _ = post(&psn, $0.baseAddress!) }
            b2.withUnsafeBufferPointer { _ = post(&psn, $0.baseAddress!) }
        }
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
        func line(_ label: String, _ r: ResolvedSym<some Any>) {
            lines.append("\(label.padding(toLength: 30, withPad: " ", startingAt: 0)) \(r.name ?? "MISSING")")
        }
        line("MainConnectionID:", mainConnR)
        line("CopyManagedDisplaySpaces:", copyManagedR)
        line("GetActiveSpace:", getActiveSpaceR)
        line("ManagedDisplaySetCurrentSpace:", setCurrentSpaceR)
        line("_SLPSSetFrontProcessWithOptions:", setFrontProcessR)
        line("SLPSPostEventRecordTo:", postEventRecordR)
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
