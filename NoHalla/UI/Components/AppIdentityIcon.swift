// The current application artwork, shared by the dashboard and native alerts.
import AppKit
import Foundation

enum AppIdentityIcon {
    static var image: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }
}
