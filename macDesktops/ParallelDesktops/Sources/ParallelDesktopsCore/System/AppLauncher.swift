import Foundation
import AppKit

/// Launches only the blueprint apps not already present on this desktop (plan U8).
public enum AppLauncher {
    /// Pure, testable dedupe: which blueprint apps need launching given the apps
    /// already present on this desktop. Scoped to "present here", not system-wide
    /// "running" — an app open only on another desktop is still launched here (U8).
    public static func toLaunch(blueprint: [String], presentHere: Set<String>) -> [String] {
        blueprint.filter { !presentHere.contains($0) }
    }

    /// Launches the missing apps. Already-present apps are neither relaunched nor
    /// duplicated (`createsNewApplicationInstance = false`).
    @discardableResult
    public static func launchMissing(blueprint: [String], presentHere: Set<String>) async -> [String] {
        var launched: [String] = []
        for bundleID in toLaunch(blueprint: blueprint, presentHere: presentHere) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                continue  // unresolvable app URL → skip with no crash (U8)
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            if (try? await NSWorkspace.shared.openApplication(at: url, configuration: config)) != nil {
                launched.append(bundleID)
            }
        }
        return launched
    }
}
