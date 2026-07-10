import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Menu-bar-only app — no Dock icon, no app switcher entry. The window
    // (calibration/onboarding/debug tools) is shown/hidden on demand from
    // the tray, never closed, so this stays running in the background.
    NSApp.setActivationPolicy(.accessory)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // The window is only ever hidden (orderOut), never actually closed, but
    // false here is the correct semantics for a background tray app either
    // way — quitting is exclusively via the tray's "Quit" item.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
