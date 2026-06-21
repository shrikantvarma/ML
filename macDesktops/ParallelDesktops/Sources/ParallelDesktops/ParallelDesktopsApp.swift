import SwiftUI
import AppKit

@main
struct ParallelDesktopsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Projects", systemImage: "square.grid.3x3.fill") {
            MenuBarListView(model: model)
        }
        .menuBarExtraStyle(.window)  // hosts a TextField + rich list (plan U10)
    }
}

/// Runtime no-Dock-icon (LSUIElement equivalent until the Xcode/Info.plist step).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
