//
//  CountdownBarView.swift
//  NoHalla
//
//  Grace countdown: linear bar plus text. At Reduce
//  Motion the bar snaps on each tick instead of animating.
//

import SwiftUI

struct CountdownBarView: View {
    let remaining: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.line)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.orange)
                        .frame(width: geometry.size.width * fraction)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: fraction)
                }
            }
            .frame(height: 4)
            Text(L10n.string("status.grace", remaining))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("status.grace", remaining))
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(remaining, total))) / CGFloat(total)
    }
}

#Preview("Countdown") {
    VStack(spacing: 12) {
        CountdownBarView(remaining: 5, total: 5)
        CountdownBarView(remaining: 2, total: 5)
        CountdownBarView(remaining: 0, total: 5)
    }
    .padding()
    .frame(width: 360)
}