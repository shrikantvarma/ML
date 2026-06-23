import Foundation

/// Pure decision for opening a project's links (plan U4): whether a Space switch is
/// needed, which Chrome profile folder to target (nil → system default browser),
/// and the http/https-filtered URLs in order. Split out so the branching is
/// unit-tested without `AppModel` (which the test target can't import).
public struct LinkOpenPlan: Equatable {
    public var needsSwitch: Bool
    public var profileFolder: String?
    public var urls: [String]          // web (http/https) → Chrome/default recipe, placed on the desktop
    public var nonWebURLs: [String]    // obsidian:// / file:// → NSWorkspace.open (routes its own window)

    public init(needsSwitch: Bool, profileFolder: String?, urls: [String], nonWebURLs: [String] = []) {
        self.needsSwitch = needsSwitch
        self.profileFolder = profileFolder
        self.urls = urls
        self.nonWebURLs = nonWebURLs
    }

    /// Build the plan from the live Space and the project's settings. `urls` is the
    /// caller's selection (all links, or one) — filtered to allowed schemes (KTD8).
    ///
    /// Profile resolution (each validated against KTD9; invalid/path-like values are
    /// rejected so they can never reach `--profile-directory`):
    ///   1. the project's explicitly-pinned `chromeProfileFolder`, else
    ///   2. `chromeFallbackFolder` — Chrome's last-used profile, so links land in the
    ///      profile the user actually works in with zero setup, else
    ///   3. nil → the system default browser (only when Chrome isn't installed).
    public static func make(project: Project, currentSpaceUUID: String?, urls: [String],
                            chromeFallbackFolder: String? = nil) -> LinkOpenPlan {
        let explicit = project.chromeProfileFolder.flatMap { ChromeProfiles.isValidFolder($0) ? $0 : nil }
        let fallback = chromeFallbackFolder.flatMap { ChromeProfiles.isValidFolder($0) ? $0 : nil }
        let allowed = urls.filter(LinkURL.isAllowed)
        return LinkOpenPlan(
            needsSwitch: currentSpaceUUID != project.spaceUUID,
            profileFolder: explicit ?? fallback,
            urls: allowed.filter(LinkURL.isWeb),
            nonWebURLs: allowed.filter { !LinkURL.isWeb($0) }
        )
    }
}
