//
//  GateSceneView.swift
//  NoHalla
//
//  Decorative gate/fjord vignette (design/COMPONENTS.md). Shares the GateScene
//  asset; treated as decoration with actions kept outside the image.
//

import SwiftUI

enum GateSceneVariant {
    case hero
    case about
    case empty
}

struct GateSceneView: View {
    let variant: GateSceneVariant

    var body: some View {
        Image("GateScene")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }

    private var height: CGFloat {
        switch variant {
        case .hero: return 160
        case .about: return 120
        case .empty: return 80
        }
    }
}

#Preview("Gate scenes") {
    VStack(spacing: 16) {
        GateSceneView(variant: .hero)
        GateSceneView(variant: .about)
        GateSceneView(variant: .empty)
    }
    .padding()
    .frame(width: 560)
}