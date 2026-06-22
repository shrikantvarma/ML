import Foundation

/// One selectable Chrome profile: the on-disk `folder` (what `--profile-directory`
/// takes, e.g. `Default`, `Profile 3`) and the user-facing `displayName` (from
/// Chrome's `Local State`). The two frequently differ (KTD6).
public struct ChromeProfile: Equatable, Identifiable {
    public var folder: String
    public var displayName: String
    public var id: String { folder }
    public init(folder: String, displayName: String) {
        self.folder = folder
        self.displayName = displayName
    }
}

/// Enumerates the user's Chrome profiles by parsing `Local State`. Pure parse split
/// from the file read, mirroring `AppLauncher` so the parse is unit-tested (plan U2).
public enum ChromeProfiles {
    /// Bound the result so a corrupted/huge `Local State` can't flood the picker (KTD: DoS guard).
    public static let maxProfiles = 20

    /// Only real, user-targetable profile folders. Drops Chrome internals like
    /// `System Profile` / `Guest Profile` and anything path-like (KTD9).
    public static func isValidFolder(_ folder: String) -> Bool {
        if folder == "Default" { return true }
        guard folder.hasPrefix("Profile "),
              let n = Int(folder.dropFirst("Profile ".count)), n >= 1 else { return false }
        return true
    }

    /// Pure: `Local State` JSON → profiles. Folder = the `info_cache` key, displayName
    /// = its `name` (falls back to the folder). Invalid folders dropped, stable order
    /// (Default first, then Profile N ascending), capped at `maxProfiles`.
    public static func parse(localStateJSON data: Data) -> [ChromeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }

        let profiles = cache.compactMap { folder, info -> ChromeProfile? in
            guard isValidFolder(folder) else { return nil }
            let name = (info as? [String: Any])?["name"] as? String ?? folder
            return ChromeProfile(folder: folder, displayName: name)
        }
        return Array(profiles.sorted { rank($0.folder) < rank($1.folder) }.prefix(maxProfiles))
    }

    /// Chrome's currently/last-used profile folder (`profile.last_used`), validated.
    /// nil when absent or not a real user profile. This is the smart fallback when a
    /// project hasn't pinned a profile — it's the one the user actually works in.
    public static func parseLastUsed(localStateJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let last = profile["last_used"] as? String,
              isValidFolder(last) else { return nil }
        return last
    }

    /// Profiles + last-used folder from a single `Local State` read.
    public struct Info: Equatable {
        public var profiles: [ChromeProfile]
        public var lastUsedFolder: String?
        public init(profiles: [ChromeProfile] = [], lastUsedFolder: String? = nil) {
            self.profiles = profiles
            self.lastUsedFolder = lastUsedFolder
        }
    }

    /// Thin: read `~/Library/Application Support/Google/Chrome/Local State` and parse.
    /// Returns `[]` when absent/unreadable — Chrome may not be installed. Callers
    /// should read off the main thread and cache (picker reads the cache, not disk).
    public static func load(from url: URL = defaultLocalStateURL) -> [ChromeProfile] {
        loadInfo(from: url).profiles
    }

    /// Like `load`, but also returns Chrome's last-used profile folder, from one read.
    public static func loadInfo(from url: URL = defaultLocalStateURL) -> Info {
        guard let data = try? Data(contentsOf: url) else { return Info() }
        return Info(profiles: parse(localStateJSON: data), lastUsedFolder: parseLastUsed(localStateJSON: data))
    }

    public static var defaultLocalStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Google/Chrome/Local State")
    }

    /// Default sorts before any Profile N; Profile N orders by its number.
    private static func rank(_ folder: String) -> Int {
        folder == "Default" ? -1 : (Int(folder.dropFirst("Profile ".count)) ?? Int.max)
    }
}
