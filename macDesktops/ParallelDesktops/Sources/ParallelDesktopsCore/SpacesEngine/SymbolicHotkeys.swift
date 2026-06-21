import Foundation

/// Best-effort read of whether macOS "Switch to Desktop N" shortcuts are enabled
/// (they default OFF). The U1 spike validates the ID mapping on the target OS.
public enum SymbolicHotkeys {
    /// "Switch to Desktop 1" is symbolic hotkey id 118; Desktop N = 117 + N.
    public static func id(forDesktop n: Int) -> Int { 117 + n }

    /// Returns true/false if readable, nil if unknown (caller attempts anyway).
    public static func switchToDesktopEnabled(_ n: Int) -> Bool? {
        let hkID = id(forDesktop: n)
        guard let dict = CFPreferencesCopyValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] else { return nil }
        guard let entry = dict[String(hkID)] as? [String: Any] else {
            return false  // no entry ⇒ never enabled (default off)
        }
        if let enabled = entry["enabled"] as? NSNumber { return enabled.boolValue }
        if let enabled = entry["enabled"] as? Bool { return enabled }
        return nil
    }
}
