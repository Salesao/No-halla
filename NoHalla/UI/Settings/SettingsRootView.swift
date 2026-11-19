//
//  SettingsRootView.swift
//  NoHalla
//
//  Settings window root (design §7.4, COMPONENTS.md settings toolbar): four
//  icon-and-text tabs (General/Protection/Advanced/About); the selected tab's
//  icon and text are blue with a 1 pt bronze underline. Window 680×520.
//

import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject var appState: AppState
    @State private var tab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, protection, advanced, about
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .general: return "ui.general"
            case .protection: return "ui.protection"
            case .advanced: return "ui.advanced"
            case .about: return "ui.about"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .protection: return "shield"
            case .advanced: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: DesignTokens.settingsWidth, height: DesignTokens.settingsHeight)
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
    }

    private var tabBar: some View {
        HStack(spacing: DesignTokens.spacing1) {
            ForEach(SettingsTab.allCases) { item in
                tabButton(item)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.spacing1)
        .background(DesignTokens.chrome)
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                Text(L10n.string(item.titleKey))
                    .font(.system(size: DesignTokens.typeSmall, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Rectangle()
                    .fill(selected ? DesignTokens.bronze : Color.clear)
                    .frame(width: 30, height: DesignTokens.ornamentStroke)
            }
            .foregroundStyle(selected ? DesignTokens.blue : DesignTokens.muted)
            .frame(width: 100, height: 48)
            .background(selected ? DesignTokens.surface : Color.clear, in: RoundedRectangle(cornerRadius: DesignTokens.radiusControl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string(item.titleKey))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: SettingsGeneralView()
        case .protection: SettingsProtectionView()
        case .advanced: SettingsAdvancedView()
        case .about: SettingsAboutView()
        }
    }
}

#Preview {
    SettingsRootView()
        .environmentObject(AppState())
}