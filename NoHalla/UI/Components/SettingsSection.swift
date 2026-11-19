// Shared grouped settings surface, matching the Doop settings panels.
import SwiftUI

struct SettingsSection<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            if let title = title {
                Text(title)
                    .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                    .foregroundStyle(DesignTokens.muted)
                    .padding(.horizontal, 2)
            }
            VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.spacing3)
            .padding(.vertical, DesignTokens.spacing2)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))
        }
    }
}
