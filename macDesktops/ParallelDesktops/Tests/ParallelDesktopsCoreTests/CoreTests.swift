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
}
