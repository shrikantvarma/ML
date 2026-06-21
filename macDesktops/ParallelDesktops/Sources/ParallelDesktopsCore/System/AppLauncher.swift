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

}
