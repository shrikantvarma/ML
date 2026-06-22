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

    func testIsValidFolder() {
        XCTAssertTrue(ChromeProfiles.isValidFolder("Default"))
        XCTAssertTrue(ChromeProfiles.isValidFolder("Profile 1"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("Profile 0"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("Profile X"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("System Profile"))
        XCTAssertFalse(ChromeProfiles.isValidFolder("../evil"))
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
                              chromeProfileFolder: "Profile 3"))
        let reopened = ProjectStore(url: url)
        let p = try XCTUnwrap(reopened.projects.first)
        XCTAssertEqual(p.blueprint.links.map(\.url), ["https://linkedin.com", "https://gmail.com"],
                       "link order must survive the round-trip")
        XCTAssertEqual(p.blueprint.links.map(\.title), ["LinkedIn", "Gmail"])
        XCTAssertEqual(p.chromeProfileFolder, "Profile 3")
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
}
