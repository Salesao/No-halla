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
        VStack(spacing: DesignTokens.spacing3) {
            GateSceneView(variant: .hero)
            Text(L10n.string("onboarding.1.title"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("onboarding.1.body"))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DesignTokens.spacing2)
            HStack {
                Button(L10n.string("onboarding.skip"), action: onSkip)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("ui.continue"), action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.spacing5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingIntroView(onContinue: {}, onSkip: {})
        .frame(width: 560, height: 420)
}