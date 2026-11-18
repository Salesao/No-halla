import SwiftUI

@main
struct NoHallaApp: App {
    @NSApplicationDelegateAdaptor(NoHallaAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text("No-halla")
                .padding(16)
        } label: {
            Image("MenuBarOff")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}