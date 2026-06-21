import Foundation
import AppKit

/// Launches only the blueprint apps that aren't running at all (plan U8).
public enum AppLauncher {
    /// Pure, testable dedupe: which blueprint apps need launching.
    ///
    /// v1 excludes apps that are **already running anywhere**, not just "present on
    /// this desktop". Activating an app that's running on another desktop can't move
    /// its window here — it only yanks focus to that desktop (and, with the macOS
    /// "switch to a Space with open windows" setting, switches Spaces). Pulling a
    /// running app's window onto this desktop needs window management (deferred), so
    /// v1 leaves already-running apps where they are.
    public static func toLaunch(blueprint: [String], alreadyRunning: Set<String>) -> [String] {
        blueprint.filter { !alreadyRunning.contains($0) }
    }

    /// Bundle IDs of every currently-running app (system-wide).
    public static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    /// Launch a not-running app; its window opens on the current desktop. Returns
    /// false if the bundle id can't be resolved to an app.
    @discardableResult
    public static func launch(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: config)) != nil
    }

    /// Best-effort "open a new window here" for an app already running elsewhere,
    /// via AppleScript `make new window`. Works for scriptable apps (browsers);
    /// returns false if the app isn't scriptable or Automation permission is denied.
    /// Caveat: macOS, not us, decides which Space the new window lands on — for some
    /// apps it may open on the app's existing Space rather than the current one.
    @discardableResult
    public static func openNewWindow(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let name = app.localizedName else { return false }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(name)\" to make new window")?
            .executeAndReturnError(&error)
        return error == nil
    }
}
