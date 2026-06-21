import Foundation
import AppKit
import CoreGraphics

public struct RunningAppInfo: Equatable {
    public let bundleID: String
    public let name: String
    public let pid: pid_t
}

/// Reads the apps with an on-screen window on the active desktop (plan U7).
///
/// Per-Space caveat (U1 step 6 / U7): `.optionOnScreenOnly` is *assumed* to mean
/// "on the active Space" — true for normal app windows in practice. If the spike
/// shows otherwise, filter PIDs through `CGSCopySpacesForWindows` here. Capture is
/// only invoked while the target desktop is active.
public enum AppInspector {
    public static func appsOnCurrentDesktop() -> [RunningAppInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var seenBundles = Set<String>()
        var result: [RunningAppInfo] = []
        for window in infoList {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  !seenBundles.contains(bundleID)
            else { continue }
            seenBundles.insert(bundleID)
            result.append(RunningAppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: pid))
        }
        return result
    }

    public static func bundleIDsOnCurrentDesktop() -> Set<String> {
        Set(appsOnCurrentDesktop().map { $0.bundleID })
    }

    /// Last on-screen window frame per app on the active desktop (plan U9/R5).
    /// Read-only; v1 never moves windows.
    public static func framesOnCurrentDesktop() -> [String: WindowFrame] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var frames: [String: WindowFrame] = [:]
        for window in infoList {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  frames[bundleID] == nil,
                  let boundsDict = window[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }
            frames[bundleID] = WindowFrame(x: rect.origin.x, y: rect.origin.y,
                                           w: rect.size.width, h: rect.size.height)
        }
        return frames
    }
}
