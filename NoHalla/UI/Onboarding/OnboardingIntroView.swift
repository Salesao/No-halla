//
//  OnboardingIntroView.swift
//  NoHalla
//
//  Onboarding step 1 of 3 (design §7.3): hero gate illustration, hero title,
//  body, Continue / Skip setup.
//

import SwiftUI

struct OnboardingIntroView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.spacing5) {
                GateSceneView(variant: .hero)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                    Text(L10n.string("onboarding.1.title"))
                        .font(.system(size: DesignTokens.typeHero, weight: .semibold))
                        .foregroundStyle(DesignTokens.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("onboarding.1.body"))
                        .font(.system(size: DesignTokens.typeBody))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .frame(maxHeight: .infinity, alignment: .center)
            HStack {
                Button(L10n.string("onboarding.skip"), action: onSkip)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignTokens.blue)
                Spacer()
                Button(L10n.string("ui.continue"), action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .padding(.vertical, DesignTokens.spacing3)
            .background(DesignTokens.chrome)
        }
        .tint(DesignTokens.action)
    }
}

#Preview {
    OnboardingIntroView(onContinue: {}, onSkip: {})
        .frame(width: 560, height: 420)
}