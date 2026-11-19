// The installed application's icon, shared by the dashboard and settings.
import AppKit
import SwiftUI

struct ProtectedAppIconView: View {
    let bundleID: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(DesignTokens.muted)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: DesignTokens.appIcon, height: DesignTokens.appIcon)
        .accessibilityHidden(true)
    }
}

#Preview("Protected app icons") {
    HStack {
        ProtectedAppIconView(bundleID: "com.apple.Terminal")
        ProtectedAppIconView(bundleID: "dev.nohalla.missing")
    }
    .padding()
}
