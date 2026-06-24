import XCTest
import CoreGraphics
import ParallelDesktopsCore

// MARK: - Fakes

final class FakeSpaces: SpacesProvider {
    var ordered: [String]
    var current: String?
    init(ordered: [String], current: String?) { self.ordered = ordered; self.current = current }
    func orderedUserSpaceUUIDs() -> [String] { ordered }
    func currentSpaceUUID() -> String? { current }
}

final class FakePoster: KeyPosting {
    var posted: [Int] = []
    // Optional hook to simulate the Space landing after a key post, so success-path
    // tests can start on a *different* Space and have the post drive the landing —
    // rather than relying on current == target (which the engine now short-circuits).
    var onPost: (() -> Void)?
    func postControlNumber(_ n: Int) {
        posted.append(n)
        onPost?()
    }
}

struct FakeSecure: SecureInputChecking {
    let active: Bool
    func isActive() -> Bool { active }
}

/// Multi-display fake: `perDisplay` rows are ordered left→right; "" marks an
/// empty-uuid desktop (macOS numbers it for Ctrl+N but it can't host a Project).
/// `currents` lists the active space of each display; `focused` is the focused
/// display's active space.
final class FakeMultiDisplaySpaces: SpacesProvider {
    let perDisplay: [[String]]; let focused: String?; let currents: [String]
    init(perDisplay: [[String]], focused: String?, currents: [String]) {
        self.perDisplay = perDisplay; self.focused = focused; self.currents = currents
    }
    func orderedUserSpaceUUIDs() -> [String] { perDisplay.first ?? [] }
    func currentSpaceUUID() -> String? { currents.first }
    func globalDesktopUUIDs() -> [String] { perDisplay.flatMap { $0 } }
    func focusedCurrentSpaceUUID() -> String? { focused }
    func isSpaceCurrent(uuid: String) -> Bool { SpaceIdentity.isTrackable(uuid) && currents.contains(uuid) }
}

// MARK: - SpaceIdentity guard + multi-display read seam (B-global Task 1)

final class SpaceIdentityTests: XCTestCase {
    func testTrackable() {
        XCTAssertTrue(SpaceIdentity.isTrackable("A1B2"))
        XCTAssertFalse(SpaceIdentity.isTrackable(""))
        XCTAssertFalse(SpaceIdentity.isTrackable("?"))
    }
}

final class MultiDisplayReadTests: XCTestCase {
    func testGlobalIndexCountsEmptiesButOnlyMatchesTrackable() {
        // display 1 has an empty desktop at position 4; "C" is global #5.
        let s = FakeMultiDisplaySpaces(perDisplay: [["A","B","C0"], ["", "C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(s.globalIndex(uuid: "C"), 5)   // counts the empty at index 4
        XCTAssertEqual(s.globalIndex(uuid: "A"), 1)
        XCTAssertNil(s.globalIndex(uuid: ""))          // never index an empty
        XCTAssertNil(s.globalIndex(uuid: "ZZ"))        // absent
    }
    func testAllTrackableExcludesEmpties() {
        let s = FakeMultiDisplaySpaces(perDisplay: [["A","B"], ["", "C"]], focused: "A", currents: ["A","C"])
        XCTAssertEqual(s.allTrackableUserSpaceUUIDs(), ["A","B","C"])
    }
    func testDefaultsFallBackToSingleDisplay() {
        let s = FakeSpaces(ordered: ["A","B"], current: "A")   // existing single-display fake
        XCTAssertEqual(s.globalDesktopUUIDs(), ["A","B"])
        XCTAssertEqual(s.focusedCurrentSpaceUUID(), "A")
        XCTAssertTrue(s.isSpaceCurrent(uuid: "A")); XCTAssertFalse(s.isSpaceCurrent(uuid: "B"))
    }
}

// MARK: - resolveIndex (KTD-2)

final class ResolveIndexTests: XCTestCase {
    func testOneBasedOrdinal() {
        let s = FakeSpaces(ordered: ["A", "B", "C"], current: "A")
        XCTAssertEqual(s.resolveIndex(uuid: "A"), 1)
        XCTAssertEqual(s.resolveIndex(uuid: "C"), 3)
    }
    func testAbsentUUIDIsNil() {
        let s = FakeSpaces(ordered: ["A", "C"], current: "A")
        XCTAssertNil(s.resolveIndex(uuid: "B"))
    }
    func testReorderChangesIndex() {
        let s = FakeSpaces(ordered: ["A", "B", "C"], current: "A")
        XCTAssertEqual(s.resolveIndex(uuid: "C"), 3)
        s.ordered = ["C", "A", "B"]
        XCTAssertEqual(s.resolveIndex(uuid: "C"), 1)
    }
}

// MARK: - RealDesktopEngine outcomes (U4 / KTD-8)

final class SwitchEngineTests: XCTestCase {
    private func engine(_ spaces: FakeSpaces, _ poster: FakePoster,
                        secure: Bool = false, shortcut: Bool? = true,
                        timeoutMs: Int = 1000) -> RealDesktopEngine {
        RealDesktopEngine(spaces: spaces, poster: poster, secureInput: FakeSecure(active: secure),
                          shortcutEnabled: { _ in shortcut }, timeoutMs: timeoutMs, pollMs: 5)
    }

    func testSwitchedResolvesPostsAndVerifies() async {
        let spaces = FakeSpaces(ordered: ["A", "B", "C"], current: "A") // a switch is needed
        let poster = FakePoster()
        poster.onPost = { spaces.current = "B" } // the key post lands us on B
        let result = await engine(spaces, poster).switch(toSpaceUUID: "B")
        XCTAssertEqual(poster.posted, [2])
        if case .switched = result {} else { XCTFail("expected .switched, got \(result)") }
    }

    func testAlreadyOnTargetShortCircuitsWithoutPosting() async {
        let spaces = FakeSpaces(ordered: ["A", "B", "C"], current: "B") // already there
        let poster = FakePoster()
        let result = await engine(spaces, poster).switch(toSpaceUUID: "B")
        XCTAssertTrue(poster.posted.isEmpty, "no key should be posted when already on target")
        if case .switched = result {} else { XCTFail("expected .switched, got \(result)") }
    }

    func testDriftWhenUUIDAbsentPostsNothing() async {
        let spaces = FakeSpaces(ordered: ["A", "C"], current: "A")
        let poster = FakePoster()
        let result = await engine(spaces, poster).switch(toSpaceUUID: "B")
        XCTAssertEqual(result, .driftDetected)
        XCTAssertTrue(poster.posted.isEmpty)
    }

    func testBlockedSecureInput() async {
        let spaces = FakeSpaces(ordered: ["A", "B"], current: "A")
        let result = await engine(spaces, FakePoster(), secure: true).switch(toSpaceUUID: "B")
        XCTAssertEqual(result, .blocked(.secureInput))
    }

    func testBlockedShortcutDisabled() async {
        let spaces = FakeSpaces(ordered: ["A", "B"], current: "A")
        let result = await engine(spaces, FakePoster(), shortcut: false).switch(toSpaceUUID: "B")
        XCTAssertEqual(result, .blocked(.shortcutDisabled))
    }

    func testVerificationFailsOnTimeoutWithoutHanging() async {
        let spaces = FakeSpaces(ordered: ["A", "B"], current: "A") // never becomes B
        let result = await engine(spaces, FakePoster(), timeoutMs: 40).switch(toSpaceUUID: "B")
        XCTAssertEqual(result, .verificationFailed)
    }

    func testNotKeyableBeyondNine() async {
        let ordered = (1...11).map { "S\($0)" }
        let spaces = FakeSpaces(ordered: ordered, current: "S1")
        let result = await engine(spaces, FakePoster()).switch(toSpaceUUID: "S10")
        XCTAssertEqual(result, .notKeyable(index: 10))
    }
}

// MARK: - Boot dedupe (U8)

final class LaunchTests: XCTestCase {
    func testExcludesAppsAlreadyRunning() {
        XCTAssertEqual(AppLauncher.toLaunch(blueprint: ["a", "b", "c"], alreadyRunning: ["b"]), ["a", "c"])
    }
    func testRunningAppIsNotRelaunched() {
        // v1: an app running anywhere is left alone (avoids the focus-yank bounce).
        XCTAssertEqual(AppLauncher.toLaunch(blueprint: ["a", "b"], alreadyRunning: ["a", "b"]), [])
    }
    func testLaunchesOnlyNotRunning() {
        XCTAssertEqual(AppLauncher.toLaunch(blueprint: ["a", "b"], alreadyRunning: []), ["a", "b"])
    }
}

// MARK: - ChromeProfiles (U2 / KTD6, KTD9)

final class ChromeProfilesTests: XCTestCase {
    private func localState(_ infoCache: String) -> Data {
        #"{ "profile": { "info_cache": \#(infoCache) } }"#.data(using: .utf8)!
    }

    func testParsesFolderAndDisplayNameIncludingMismatch() {
        // Folder "Default" displayed as "Personal" — the real-world mismatch (KTD6).
        let data = localState(#"{ "Default": { "name": "Personal" }, "Profile 3": { "name": "Work" } }"#)
        let profiles = ChromeProfiles.parse(localStateJSON: data)
        XCTAssertEqual(profiles, [ChromeProfile(folder: "Default", displayName: "Personal"),
                                  ChromeProfile(folder: "Profile 3", displayName: "Work")])
    }

    func testStableOrderDefaultFirstThenNumeric() {
        let data = localState(#"{ "Profile 10": { "name": "J" }, "Profile 2": { "name": "B" }, "Default": { "name": "A" } }"#)
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: data).map(\.folder),
                       ["Default", "Profile 2", "Profile 10"])
    }

    func testTwoProfilesShareDisplayName() {
        let data = localState(#"{ "Default": { "name": "Shrikant" }, "Profile 1": { "name": "Shrikant" } }"#)
        let profiles = ChromeProfiles.parse(localStateJSON: data)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.map(\.folder)), ["Default", "Profile 1"])
    }

    func testFolderPatternGuardDropsInternalAndPathLike() {
        let data = localState(#"{ "Default": { "name": "A" }, "System Profile": { "name": "Sys" }, "../evil": { "name": "X" }, "Guest Profile": { "name": "G" } }"#)
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: data).map(\.folder), ["Default"])
    }

    func testMissingNameFallsBackToFolder() {
        let data = localState(#"{ "Profile 1": { } }"#)
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: data),
                       [ChromeProfile(folder: "Profile 1", displayName: "Profile 1")])
    }

    func testMalformedAndEmptyYieldEmpty() {
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: Data()), [])
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: "not json".data(using: .utf8)!), [])
        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: #"{ "profile": {} }"#.data(using: .utf8)!), [])
    }

    func testParseLastUsedReturnsValidFolder() {
        let data = #"{ "profile": { "last_used": "Profile 3", "info_cache": { "Profile 3": { "name": "Shrikant" } } } }"#.data(using: .utf8)!
        XCTAssertEqual(ChromeProfiles.parseLastUsed(localStateJSON: data), "Profile 3")
    }

    func testParseLastUsedRejectsInvalidOrMissing() {
        // Internal folder name → rejected (KTD9).
        let internalFolder = #"{ "profile": { "last_used": "System Profile", "info_cache": {} } }"#.data(using: .utf8)!
        XCTAssertNil(ChromeProfiles.parseLastUsed(localStateJSON: internalFolder))
        // Missing key → nil.
        XCTAssertNil(ChromeProfiles.parseLastUsed(localStateJSON: #"{ "profile": {} }"#.data(using: .utf8)!))
        XCTAssertNil(ChromeProfiles.parseLastUsed(localStateJSON: Data()))
    }

    func testIsValidFolder() {
        XCTAssertTrue(ChromeProfiles.isValidFolder("Default"))
        XCTAssertTrue(ChromeProfiles.isValidFolder("Profile 1"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("Profile 0"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("Profile X"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("System Profile"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("../evil"))
    }
}

// MARK: - BrowserLauncher (U3 / KTD3, KTD4, KTD8)

final class BrowserLauncherTests: XCTestCase {
    func testArgumentsSingleURL() {
        XCTAssertEqual(
            ChromeCommand.arguments(profileFolder: "Default", urls: ["https://x.com"]),
            ["-na", "Google Chrome", "--args", "--new-window", "--profile-directory=Default", "https://x.com"])
    }

    func testArgumentsMultipleURLsPreserveOrder() {
        let args = ChromeCommand.arguments(profileFolder: "Profile 3",
                                           urls: ["https://a.com", "https://b.com", "https://c.com"])
        XCTAssertEqual(Array(args.suffix(3)), ["https://a.com", "https://b.com", "https://c.com"])
        XCTAssertEqual(args[3], "--new-window")
    }

    func testProfileFolderWithSpaceIsOneToken() {
        let args = ChromeCommand.arguments(profileFolder: "Profile 3", urls: ["https://x.com"])
        XCTAssertTrue(args.contains("--profile-directory=Profile 3"),
                      "folder with a space must be a single argv token, not split")
    }

    func testArgumentsEmptyURLs() {
        XCTAssertEqual(ChromeCommand.arguments(profileFolder: "Default", urls: []),
                       ["-na", "Google Chrome", "--args", "--new-window", "--profile-directory=Default"])
    }

    func testIsAllowedScheme() {
        XCTAssertTrue(LinkURL.isAllowed("https://x.com"))
        XCTAssertTrue(LinkURL.isAllowed("http://x.com"))
        XCTAssertTrue(LinkURL.isAllowed("HTTPS://x.com"))
        XCTAssertTrue(LinkURL.isAllowed("obsidian://open?vault=v&file=f"))  // notes doc (U2)
        XCTAssertTrue(LinkURL.isAllowed("file:///Users/me/notes.md"))       // local doc (U2)
        XCTAssertFalse(LinkURL.isAllowed("javascript:alert(1)"))
        XCTAssertFalse(LinkURL.isAllowed("x-apple.systempreferences://x"))
        XCTAssertFalse(LinkURL.isAllowed("x.com"))
        XCTAssertFalse(LinkURL.isAllowed(""))
    }

    func testIsWeb() {
        XCTAssertTrue(LinkURL.isWeb("https://x.com"))
        XCTAssertTrue(LinkURL.isWeb("http://x.com"))
        XCTAssertFalse(LinkURL.isWeb("obsidian://open?vault=v"))  // allowed but non-web
        XCTAssertFalse(LinkURL.isWeb("file:///a/b.md"))
        XCTAssertFalse(LinkURL.isWeb("x.com"))
    }
}

// MARK: - LinkOpenPlan (U4)

final class LinkOpenPlanTests: XCTestCase {
    private func project(space: String, profile: String?, links: [String]) -> Project {
        Project(name: "P", spaceUUID: space,
                blueprint: Blueprint(links: links.map { Link(url: $0, title: $0) }),
                chromeProfileFolder: profile)
    }

    func testNoSwitchWhenAlreadyOnSpace() {
        let p = project(space: "S1", profile: nil, links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1", urls: p.blueprint.links.map(\.url))
        XCTAssertFalse(plan.needsSwitch)
    }

    func testSwitchWhenOnDifferentSpace() {
        let p = project(space: "S1", profile: nil, links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S2", urls: p.blueprint.links.map(\.url))
        XCTAssertTrue(plan.needsSwitch)
    }

    func testProfilePresenceSelectsPath() {
        let withProfile = project(space: "S1", profile: "Profile 3", links: ["https://x.com"])
        XCTAssertEqual(LinkOpenPlan.make(project: withProfile, currentSpaceUUID: "S1",
                                         urls: ["https://x.com"]).profileFolder, "Profile 3")
        let noProfile = project(space: "S1", profile: nil, links: ["https://x.com"])
        XCTAssertNil(LinkOpenPlan.make(project: noProfile, currentSpaceUUID: "S1",
                                       urls: ["https://x.com"]).profileFolder)
    }

    func testURLsFilteredAndOrderPreserved() {
        let p = project(space: "S1", profile: nil, links: [])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://a.com", "javascript:alert(1)", "https://b.com"])
        XCTAssertEqual(plan.urls, ["https://a.com", "https://b.com"], "disallowed schemes dropped, order kept")
    }

    func testWebAndNonWebPartition() {
        // Allowed schemes split: web → urls (Chrome recipe), obsidian/file → nonWebURLs (NSWorkspace).
        let p = project(space: "S1", profile: nil, links: [])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://a.com", "obsidian://open?file=note", "file:///a/b.md",
                                            "javascript:bad"])
        XCTAssertEqual(plan.urls, ["https://a.com"], "only web links get the desktop-placement recipe")
        XCTAssertEqual(plan.nonWebURLs, ["obsidian://open?file=note", "file:///a/b.md"],
                       "obsidian/file route to NSWorkspace; disallowed scheme dropped entirely")
    }

    func testEmptyLinksEmptyPlan() {
        let p = project(space: "S1", profile: nil, links: [])
        XCTAssertTrue(LinkOpenPlan.make(project: p, currentSpaceUUID: "S1", urls: []).urls.isEmpty)
    }

    func testValidProfileFolderKept() {
        let p = project(space: "S1", profile: "Profile 3", links: ["https://x.com"])
        XCTAssertEqual(LinkOpenPlan.make(project: p, currentSpaceUUID: "S1", urls: ["https://x.com"]).profileFolder,
                       "Profile 3")
    }

    func testInvalidProfileFolderRejectedToDefault() {
        // A hand-edited/synced path-like folder must never reach --profile-directory (KTD9).
        let p = project(space: "S1", profile: "../../evil", links: ["https://x.com"])
        XCTAssertNil(LinkOpenPlan.make(project: p, currentSpaceUUID: "S1", urls: ["https://x.com"]).profileFolder,
                     "invalid folder falls back to the default browser path")
    }

    func testFallbackUsedWhenNoExplicitProfile() {
        let p = project(space: "S1", profile: nil, links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://x.com"], chromeFallbackFolder: "Profile 3")
        XCTAssertEqual(plan.profileFolder, "Profile 3", "no explicit profile → Chrome's last-used")
    }

    func testExplicitProfileBeatsFallback() {
        let p = project(space: "S1", profile: "Profile 5", links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://x.com"], chromeFallbackFolder: "Profile 3")
        XCTAssertEqual(plan.profileFolder, "Profile 5", "explicit pin wins over the fallback")
    }

    func testInvalidFallbackIgnored() {
        let p = project(space: "S1", profile: nil, links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://x.com"], chromeFallbackFolder: "PPDTest")
        XCTAssertNil(plan.profileFolder, "an invalid fallback folder → default browser, never --profile-directory")
    }

    func testNoFallbackWhenChromeAbsent() {
        let p = project(space: "S1", profile: nil, links: ["https://x.com"])
        let plan = LinkOpenPlan.make(project: p, currentSpaceUUID: "S1",
                                     urls: ["https://x.com"], chromeFallbackFolder: nil)
        XCTAssertNil(plan.profileFolder, "no explicit + no fallback → default browser")
    }
}

// MARK: - Key code mapping (U4)

final class KeyCodeTests: XCTestCase {
    func testNonContiguousDigitCodes() {
        XCTAssertEqual(CGEventKeyPoster.keyCode(forDesktop: 1), 0x12)
        XCTAssertEqual(CGEventKeyPoster.keyCode(forDesktop: 5), 0x17) // out of order
        XCTAssertEqual(CGEventKeyPoster.keyCode(forDesktop: 6), 0x16)
        XCTAssertNil(CGEventKeyPoster.keyCode(forDesktop: 10))
    }
}

// MARK: - ProjectSearch (U11 / AE4)

final class ProjectSearchTests: XCTestCase {
    private func projects(_ names: [String]) -> [Project] {
        names.map { Project(name: $0, spaceUUID: "U-\($0)") }
    }
    func testPrefixMatchRanksFirst() {
        let all = projects(["Sales", "Marketing", "Admin", "Research", "Salsa", "Content", "Ops", "Finance"])
        let result = ProjectSearch.match(query: "sa", in: all)
        XCTAssertEqual(result.first?.name, "Sales") // prefix match wins; covers AE4
        XCTAssertTrue(result.contains { $0.name == "Salsa" })
    }
    func testCaseInsensitiveAndMidString() {
        let all = projects(["Marketing", "Admin"])
        XCTAssertEqual(ProjectSearch.match(query: "MIN", in: all).map { $0.name }, ["Admin"])
    }
    func testEmptyQueryReturnsAll() {
        let all = projects(["A", "B"])
        XCTAssertEqual(ProjectSearch.match(query: "  ", in: all).count, 2)
    }
    func testNoMatchIsEmpty() {
        XCTAssertTrue(ProjectSearch.match(query: "zzz", in: projects(["A", "B"])).isEmpty)
    }
}

// MARK: - DriftDetector (U5)

final class DriftDetectorTests: XCTestCase {
    func testReorderSameSet() {
        XCTAssertEqual(DriftDetector.diff(old: ["A", "B", "C"], new: ["C", "A", "B"]), .reordered)
    }
    func testUnchangedWhenIdentical() {
        XCTAssertEqual(DriftDetector.diff(old: ["A", "B"], new: ["A", "B"]), .unchanged)
    }
    func testRemoval() {
        XCTAssertEqual(DriftDetector.diff(old: ["A", "B", "C"], new: ["A", "C"]), .removed(["B"]))
    }
    func testAddition() {
        XCTAssertEqual(DriftDetector.diff(old: ["A"], new: ["A", "B"]), .added(["B"]))
    }
    func testMixed() {
        XCTAssertEqual(DriftDetector.diff(old: ["A", "B"], new: ["A", "C"]),
                       .mixed(added: ["C"], removed: ["B"]))
    }
    func testDriftedUUIDsAreThoseMissing() {
        // A bound project whose desktop was removed is drifted; reordered ones are not.
        let drifted = DriftDetector.driftedUUIDs(bound: ["A", "B", "Z"], in: ["B", "A", "C"])
        XCTAssertEqual(drifted, ["Z"])
    }
}

// MARK: - ProjectStore (U6 / KTD-6)

final class ProjectStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pdtest-\(UUID().uuidString).json")
    }

    func testRoundTripAcrossInstances() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(url: url)
        try store.add(Project(name: "Sales", spaceUUID: "U1", blueprint: Blueprint(bundleIDs: ["com.a"])))
        let reopened = ProjectStore(url: url)
        XCTAssertEqual(reopened.projects.count, 1)
        XCTAssertEqual(reopened.projects.first?.name, "Sales")
        XCTAssertEqual(reopened.projects.first?.spaceUUID, "U1")
        XCTAssertEqual(reopened.projects.first?.blueprint.bundleIDs, ["com.a"])
    }

    func testMissingFileIsEmpty() {
        let store = ProjectStore(url: tempURL())
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testCorruptFileIsPreservedNotClobbered() throws {
        let url = tempURL(); defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        try "not json".data(using: .utf8)!.write(to: url)
        let store = ProjectStore(url: url)           // corrupt → start empty, back up
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                      "corrupt file must be backed up, not silently overwritten")
        store.save()                                  // must not destroy the backup
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    func testCapExceeded() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(url: url)
        for i in 0..<ProjectStore.maxProjects {
            try? store.add(Project(name: "P\(i)", spaceUUID: "U\(i)"))
        }
        XCTAssertThrowsError(try store.add(Project(name: "over", spaceUUID: "Uover"))) { error in
            XCTAssertEqual(error as? ProjectStore.StoreError, .capExceeded)
        }
    }

    // MARK: U1 — links + profile persistence and migration safety

    func testLinksAndProfileRoundTrip() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let links = [Link(url: "https://linkedin.com", title: "LinkedIn"),
                     Link(url: "https://gmail.com", title: "Gmail")]
        let store = ProjectStore(url: url)
        try store.add(Project(name: "Comms", spaceUUID: "U1",
                              blueprint: Blueprint(bundleIDs: ["com.a"], links: links),
                              chromeProfileFolder: "Profile 3", iconName: "megaphone.fill"))
        let reopened = ProjectStore(url: url)
        let p = try XCTUnwrap(reopened.projects.first)
        XCTAssertEqual(p.blueprint.links.map(\.url), ["https://linkedin.com", "https://gmail.com"],
                       "link order must survive the round-trip")
        XCTAssertEqual(p.blueprint.links.map(\.title), ["LinkedIn", "Gmail"])
        XCTAssertEqual(p.chromeProfileFolder, "Profile 3")
        XCTAssertEqual(p.iconName, "megaphone.fill")
    }

    /// The migration guarantee (KTD1): an existing file with no `links` key (and no
    /// `chromeProfileFolder`) decodes to defaults — it must NOT be quarantined.
    func testMissingLinksKeyDecodesToDefaultsNotQuarantined() throws {
        let url = tempURL(); defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        // Hand-written "old" file: blueprint has no `links`, project has no profile.
        let legacy = """
        {
          "schemaVersion": 1,
          "projects": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Legacy",
              "spaceUUID": "U1",
              "blueprint": { "bundleIDs": ["com.a"], "frames": {} },
              "resume": {},
              "drifted": false
            }
          ]
        }
        """
        try legacy.data(using: .utf8)!.write(to: url)
        let store = ProjectStore(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "a missing links key is a migration, not corruption")
        let p = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(p.name, "Legacy")
        XCTAssertEqual(p.blueprint.links, [], "missing links key → empty default")
        XCTAssertNil(p.chromeProfileFolder, "missing profile key → nil default")
    }

    /// The other side of the boundary: `links` present but wrong-typed is genuine
    /// corruption and still quarantines.
    func testMalformedLinksValueIsQuarantined() throws {
        let url = tempURL(); defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let bad = """
        {
          "schemaVersion": 1,
          "projects": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Bad",
              "spaceUUID": "U1",
              "blueprint": { "bundleIDs": [], "frames": {}, "links": "not-an-array" },
              "resume": {},
              "drifted": false
            }
          ]
        }
        """
        try bad.data(using: .utf8)!.write(to: url)
        let store = ProjectStore(url: url)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                      "present-but-malformed links must quarantine, not silently default")
    }

    func testLinkEquatable() {
        let id = UUID()
        XCTAssertEqual(Link(id: id, url: "https://x.com", title: "X"),
                       Link(id: id, url: "https://x.com", title: "X"))
        XCTAssertNotEqual(Link(id: id, url: "https://x.com", title: "X"),
                          Link(id: id, url: "https://y.com", title: "X"))
    }

    // MARK: U1 — checklist persistence and migration safety

    func testChecklistRoundTrip() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let items = [ChecklistItem(text: "Reply to investor", done: true),
                     ChecklistItem(text: "Ship link fix", done: false)]
        let store = ProjectStore(url: url)
        try store.add(Project(name: "Comms", spaceUUID: "U1",
                              blueprint: Blueprint(checklist: items)))
        let reopened = ProjectStore(url: url)
        let cl = try XCTUnwrap(reopened.projects.first).blueprint.checklist
        XCTAssertEqual(cl.map(\.text), ["Reply to investor", "Ship link fix"], "order preserved")
        XCTAssertEqual(cl.map(\.done), [true, false], "done flags preserved")
    }

    /// Migration (KTD1): an existing file with no `checklist` key decodes to [] — not quarantined.
    func testMissingChecklistKeyDecodesToDefaultsNotQuarantined() throws {
        let url = tempURL(); defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let legacy = """
        {
          "schemaVersion": 1,
          "projects": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Legacy",
              "spaceUUID": "U1",
              "blueprint": { "bundleIDs": ["com.a"], "frames": {}, "links": [] },
              "resume": {},
              "drifted": false
            }
          ]
        }
        """
        try legacy.data(using: .utf8)!.write(to: url)
        let store = ProjectStore(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "a missing checklist key is a migration, not corruption")
        XCTAssertEqual(try XCTUnwrap(store.projects.first).blueprint.checklist, [])
    }

    func testMalformedChecklistValueIsQuarantined() throws {
        let url = tempURL(); defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }
        let bad = """
        {
          "schemaVersion": 1,
          "projects": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Bad",
              "spaceUUID": "U1",
              "blueprint": { "bundleIDs": [], "frames": {}, "checklist": "not-an-array" },
              "resume": {},
              "drifted": false
            }
          ]
        }
        """
        try bad.data(using: .utf8)!.write(to: url)
        let store = ProjectStore(url: url)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                      "present-but-malformed checklist must quarantine, not silently default")
    }

    func testChecklistItemEquatable() {
        let id = UUID()
        XCTAssertEqual(ChecklistItem(id: id, text: "A", done: false),
                       ChecklistItem(id: id, text: "A", done: false))
        XCTAssertNotEqual(ChecklistItem(id: id, text: "A", done: false),
                          ChecklistItem(id: id, text: "A", done: true))
    }
}
