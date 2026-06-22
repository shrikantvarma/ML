import Foundation
import AppKit

/// URL safety gate (KTD8). Only http/https links may be opened — a pasted or
/// synced `file://`, `javascript:`, or custom-scheme string must never reach
/// `open`/`NSWorkspace`, which would launch an unintended/privileged handler.
public enum LinkURL {
    public static func isAllowed(_ raw: String) -> Bool {
        guard let scheme = URLComponents(string: raw)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// Builds the validated Chrome open command (KTD3/KTD4). Pure and byte-exact so it
/// is unit-tested; the side-effecting run lives in `SystemURLOpener`.
public enum ChromeCommand {
    /// argv for `/usr/bin/open`: a single new Chrome window in the given profile
    /// folder, with every URL as a trailing arg (Chrome opens them as tabs). The
    /// window is born on whatever Space is active at creation — callers must switch
    /// and settle first (KTD5).
    public static func arguments(profileFolder: String, urls: [String]) -> [String] {
        ["-na", "Google Chrome", "--args", "--new-window",
         "--profile-directory=\(profileFolder)"] + urls
    }
}

/// The single browser-opening boundary (plan U3), mirroring `SwitchEngine` so the
/// open path can be faked in tests and a non-Chromium opener can drop in later.
public protocol URLOpening {
    /// Open `urls` in a new window of the given Chrome profile folder. Returns false
    /// if nothing valid to open or the launch failed (e.g. Chrome not installed).
    func openChrome(profileFolder: String, urls: [String]) -> Bool
    /// Open one URL in the system default browser (no-profile path, KTD7).
    func openDefault(url: String) -> Bool
}

/// Production opener: `Process`→`/usr/bin/open` for the Chrome recipe (the first
/// shell-out in the app — non-sandboxed, see plan Risks), `NSWorkspace` for the
/// default path. Both gate on `LinkURL.isAllowed` as a last line of defense.
public struct SystemURLOpener: URLOpening {
    public init() {}

    public func openChrome(profileFolder: String, urls: [String]) -> Bool {
        let allowed = urls.filter(LinkURL.isAllowed)
        guard !allowed.isEmpty else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ChromeCommand.arguments(profileFolder: profileFolder, urls: allowed)
        do {
            try proc.run()
            proc.waitUntilExit()                 // `open` returns promptly
            return proc.terminationStatus == 0   // non-zero ⇒ e.g. Chrome not installed
        } catch {
            return false
        }
    }

    public func openDefault(url: String) -> Bool {
        guard LinkURL.isAllowed(url), let u = URL(string: url) else { return false }
        return NSWorkspace.shared.open(u)
    }
}
