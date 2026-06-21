import Foundation
import Carbon                 // IsSecureEventInputEnabled
import ApplicationServices    // AXIsProcessTrusted / AXIsProcessTrustedWithOptions

// The three named failure modes from the plan (U4 / KTD-8) plus persistence for
// the UUID-survives-reboot gate condition.

enum Probes {
    /// Secure Input silently swallows synthesized key events (a password field,
    /// some terminals/password managers). Point-in-time check.
    static func secureInputEnabled() -> Bool {
        return IsSecureEventInputEnabled()
    }

    /// Accessibility (TCC) gates BOTH AX title reading and CGEvent posting.
    static func accessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    /// "Switch to Desktop N" symbolic-hotkey IDs begin at 118 for Desktop 1.
    /// (Best-effort mapping — the spike is what validates it on this OS.)
    static func symbolicHotkeyID(forDesktop n: Int) -> Int { 117 + n }

    /// Reads com.apple.symbolichotkeys to see whether the Switch-to-Desktop-N
    /// shortcut is enabled. nil = couldn't read (treat as unknown, attempt anyway).
    static func shortcutEnabled(desktop n: Int) -> Bool? {
        let hkID = symbolicHotkeyID(forDesktop: n)
        guard let dict = CFPreferencesCopyValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] else { return nil }
        guard let entry = dict[String(hkID)] as? [String: Any] else {
            // No entry usually means never-enabled — these shortcuts default OFF.
            return false
        }
        if let enabled = entry["enabled"] as? NSNumber { return enabled.boolValue }
        if let enabled = entry["enabled"] as? Bool { return enabled }
        return nil
    }
}

/// A persisted project→Space binding, keyed by Space UUID (KTD-2 / KTD-6).
/// Survives process exit so the reboot test (gate condition d) is possible.
struct Binding: Codable {
    let name: String
    let uuid: String
    let managedSpaceID: Int64
    let boundAt: Date
}

enum Store {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ParallelDesktopsSpike", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("binding.json")
    }

    static func save(_ b: Binding) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(b) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func load() -> Binding? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Binding.self, from: data)
    }
}
