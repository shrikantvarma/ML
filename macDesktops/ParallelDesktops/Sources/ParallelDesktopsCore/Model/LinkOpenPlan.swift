import Foundation

/// Pure decision for opening a project's links (plan U4): whether a Space switch is
/// needed, which Chrome profile folder to target (nil → system default browser),
/// and the http/https-filtered URLs in order. Split out so the branching is
/// unit-tested without `AppModel` (which the test target can't import).
public struct LinkOpenPlan: Equatable {
    public var needsSwitch: Bool
    public var profileFolder: String?
    public var urls: [String]

    public init(needsSwitch: Bool, profileFolder: String?, urls: [String]) {
        self.needsSwitch = needsSwitch
        self.profileFolder = profileFolder
        self.urls = urls
    }

    /// Build the plan from the live Space and the project's settings. `urls` is the
    /// caller's selection (all links, or one) — filtered to allowed schemes (KTD8).
    public static func make(project: Project, currentSpaceUUID: String?, urls: [String]) -> LinkOpenPlan {
        LinkOpenPlan(
            needsSwitch: currentSpaceUUID != project.spaceUUID,
            profileFolder: project.chromeProfileFolder,
            urls: urls.filter(LinkURL.isAllowed)
        )
    }
}
