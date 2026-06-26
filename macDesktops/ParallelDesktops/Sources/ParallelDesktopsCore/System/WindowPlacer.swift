import Foundation
import AppKit
import ApplicationServices

/// Places a freshly-opened browser window onto a target display (plan: cross-display
/// link open, Atom 2). macOS opens a new Chrome window on the display where Chrome's
/// FRONTMOST window already is — not the focused display, not the current Space (proven
/// on-device). So after we open, we move the new window onto the project's display,
/// whose current Space we've already set (Atom 1). Moving across DISPLAYS is a plain
/// coordinate change (the SIP wall is only cross-Space on ONE display), done here via
/// the Accessibility API the app already holds — no new Automation/TCC permission.
public protocol WindowPlacing {
    /// Number of windows `bundleID` currently owns (call BEFORE opening, so the new
    /// one can be singled out by count).
    func windowCount(bundleID: String) -> Int
    /// Poll up to `timeoutMs` for the window count to exceed `priorCount` (the new
    /// window appeared), then move the frontmost window's top-left onto `bounds`.
    /// Returns true iff a window was found and moved. Blocking — call off the main actor.
    func placeNewFrontWindow(bundleID: String, priorCount: Int, onto bounds: CGRect, timeoutMs: Int) -> Bool
}

/// Production placer over the Accessibility API. `--new-window` makes the new window
/// frontmost, so once the count grows we move element `windows[0]`.
public struct AXWindowPlacer: WindowPlacing {
    public init() {}

    private func appElement(_ bundleID: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
        else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func windows(_ el: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    public func windowCount(bundleID: String) -> Int {
        guard let el = appElement(bundleID) else { return 0 }
        return windows(el).count
    }

    public func placeNewFrontWindow(bundleID: String, priorCount: Int, onto bounds: CGRect, timeoutMs: Int) -> Bool {
        guard let el = appElement(bundleID) else { return false }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var wins = windows(el)
        while wins.count <= priorCount && Date() < deadline {
            usleep(50_000)   // 50ms — `open` births the window a beat after it returns
            wins = windows(el)
        }
        guard wins.count > priorCount, let newWindow = wins.first else { return false }
        // Inset a little from the display's corner so the title bar is comfortably on-screen.
        var origin = CGPoint(x: bounds.origin.x + 40, y: bounds.origin.y + 40)
        guard let posValue = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(newWindow, kAXPositionAttribute as CFString, posValue) == .success
    }
}
