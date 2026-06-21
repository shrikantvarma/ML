import Foundation
import AppKit
import ApplicationServices

/// Reads the focused window title of the frontmost app via the Accessibility API
/// (plan KTD-5 / U12). Degrades to nil without Accessibility rather than crashing.
public enum AXTitleReader {
    public static func focusedWindowTitle() -> String? {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(front.processIdentifier)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        let window = windowRef as! AXUIElement

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }
}

/// Permission/readiness checks (plan U14).
public enum Permissions {
    public static func accessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    /// True if at least one Switch-to-Desktop shortcut (1...maxDesktops) is enabled.
    public static func anySwitchShortcutEnabled(maxDesktops: Int = 9) -> Bool {
        (1...max(1, maxDesktops)).contains { SymbolicHotkeys.switchToDesktopEnabled($0) == true }
    }
}
