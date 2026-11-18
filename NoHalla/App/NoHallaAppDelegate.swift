import AppKit

final class NoHallaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // S1 wiring installs single-instance guard, stores and engine here.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // S2 lifecycle resumes frozen processes and stops the watchdog here.
    }
}