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
    }

    private var tabBar: some View {
        HStack(spacing: DesignTokens.spacing5) {
            ForEach(SettingsTab.allCases) { item in
                tabButton(item)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacing4)
        .padding(.top, DesignTokens.spacing3)
        .background(DesignTokens.chrome)
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            VStack(spacing: DesignTokens.spacing1) {
                HStack(spacing: DesignTokens.spacing1) {
                    Image(systemName: item.symbol)
                    Text(L10n.string(item.titleKey))
                }
                .font(.system(size: DesignTokens.typeBody, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DesignTokens.blue : DesignTokens.muted)
                Rectangle()
                    .fill(selected ? DesignTokens.bronze : Color.clear)
                    .frame(height: DesignTokens.ornamentStroke)
            }
            .frame(minHeight: DesignTokens.targetMin)
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