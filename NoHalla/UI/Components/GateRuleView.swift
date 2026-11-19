//
//  GateRuleView.swift
//  NoHalla
//
//  Decorative bronze divider with 24 strokes (design/COMPONENTS.md, ornament
//  tokens). Hidden from assistive technology; carries no meaning.
//

import SwiftUI

struct GateRuleView: View {
    var body: some View {
        Canvas { context, size in
            let stroke = DesignTokens.ornamentStroke
            let ticks = DesignTokens.ornamentTicks
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: midY))
            line.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(line, with: .color(DesignTokens.bronze), lineWidth: stroke)
            guard ticks > 0 else { return }
            let step = size.width / CGFloat(ticks)
            let tickHeight: CGFloat = 4
            for index in 0..<ticks {
                let x = step * (CGFloat(index) + 0.5)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: midY - tickHeight / 2))
                tick.addLine(to: CGPoint(x: x, y: midY + tickHeight / 2))
                context.stroke(tick, with: .color(DesignTokens.bronze), lineWidth: stroke)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

#Preview {
    GateRuleView()
        .padding()
        .frame(width: 360)
}