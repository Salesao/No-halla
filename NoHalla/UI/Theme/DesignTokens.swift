//
//  DesignTokens.swift
//  NoHalla
//
//  Design tokens mirrored verbatim from design/tokens.json (design brief §10).
//  Colors are dynamic: light/dark follow the effective appearance, and the
//  third tokens.json column ("contrast", appearance[2]) is used when the user
//  enables Increase Contrast. Sizes, spacing, radii, type sizes, ornament and
//  badge tint values are the literal token values. System SF Pro only, no
//  custom fonts. The status-to-glyph mapping is created in the wiring layer,
//  not here.
//

import AppKit
import SwiftUI

/// Design tokens from `design/tokens.json`.
enum DesignTokens {
    // MARK: - Colors (light / dark / increase-contrast)

    static let bg: Color = dynamicColor(name: "bg", light: "#f5f6fa", dark: "#0e1f26", contrast: "#ffffff")
    static let surface: Color = dynamicColor(name: "surface", light: "#ffffff", dark: "#1c333d", contrast: "#ffffff")
    static let text: Color = dynamicColor(name: "text", light: "#182130", dark: "#f2f5fa", contrast: "#141414")
    static let muted: Color = dynamicColor(name: "muted", light: "#515f72", dark: "#a9b8c4", contrast: "#393939")
    static let line: Color = dynamicColor(name: "line", light: "#d9e0eb", dark: "#2e4a52", contrast: "#6b6b6b")
    static let blue: Color = dynamicColor(name: "blue", light: "#1557ad", dark: "#94bcff", contrast: "#004aab")
    static let action: Color = dynamicColor(name: "action", light: "#1b5ec4", dark: "#2865c6", contrast: "#004aab")
    static let onAction: Color = dynamicColor(name: "on-action", light: "#ffffff", dark: "#ffffff", contrast: "#ffffff")
    static let green: Color = dynamicColor(name: "green", light: "#196542", dark: "#88ddb1", contrast: "#12582e")
    static let orange: Color = dynamicColor(name: "orange", light: "#854600", dark: "#ffc784", contrast: "#713d00")
    static let red: Color = dynamicColor(name: "red", light: "#a42338", dark: "#ffa1af", contrast: "#930000")
    static let fjord: Color = dynamicColor(name: "fjord", light: "#16323b", dark: "#0e1f26", contrast: "#16323b")
    static let fjordLight: Color = dynamicColor(name: "fjord-light", light: "#2a4a55", dark: "#1c333d", contrast: "#2a4a55")
    static let bronze: Color = dynamicColor(name: "bronze", light: "#b5763a", dark: "#d9a066", contrast: "#b5763a")
    static let metalLight: Color = dynamicColor(name: "metal-light", light: "#d9a066", dark: "#e8be8a", contrast: "#d9a066")
    static let bone: Color = dynamicColor(name: "bone", light: "#e8e0d0", dark: "#e8e0d0", contrast: "#e8e0d0")
    static let ember: Color = dynamicColor(name: "ember", light: "#c65a3a", dark: "#d9765a", contrast: "#c65a3a")
    static let chrome: Color = dynamicColor(name: "chrome", light: "#eef1f7", dark: "#14252d", contrast: "#ffffff")
    static let control: Color = dynamicColor(name: "control", light: "#f0f3f8", dark: "#24404b", contrast: "#ffffff")
    static let controlLine: Color = dynamicColor(name: "control-line", light: "#7b889c", dark: "#7e8da3", contrast: "#6b6b6b")

    // MARK: - Color aliases (verbatim tokens.json key spellings)

    static let `on-action`: Color = onAction
    static let `fjord-light`: Color = fjordLight
    static let `metal-light`: Color = metalLight
    static let `control-line`: Color = controlLine

    // MARK: - Sizes (points, tokens.json size)

    static let popoverWidth: CGFloat = 360
    static let settingsWidth: CGFloat = 680
    static let settingsHeight: CGFloat = 520
    static let onboardingWidth: CGFloat = 560
    static let onboardingHeight: CGFloat = 420
    static let pickerWidth: CGFloat = 480
    static let pickerHeight: CGFloat = 520
    static let appRow: CGFloat = 44
    static let appIcon: CGFloat = 20
    static let menuBar: CGFloat = 18
    static let statusHeight: CGFloat = 22
    static let targetMin: CGFloat = 28

    // MARK: - Spacing (tokens.json spacing: 4 / 8 / 12 / 16 / 24)

    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing5: CGFloat = 24

    // MARK: - Corner radii (tokens.json radii)

    static let radiusControl: CGFloat = 6
    static let radiusCard: CGFloat = 10
    static let radiusWindow: CGFloat = 14
    static let radiusPill: CGFloat = 11

    // MARK: - Typography (tokens.json type; system SF Pro, no custom fonts)

    static let typeBody: CGFloat = 13
    static let typeSmall: CGFloat = 11
    static let typeTitle: CGFloat = 17
    static let typeHero: CGFloat = 23

    static let bodyFont: Font = .system(size: typeBody)
    static let smallFont: Font = .system(size: typeSmall)
    static let titleFont: Font = .system(size: typeTitle)
    static let heroFont: Font = .system(size: typeHero)

    // MARK: - Ornament (tokens.json ornament; role color is `bronze`)

    static let ornamentStroke: CGFloat = 1
    static let ornamentTicks: Int = 24

    // MARK: - Badge tint (tokens.json badgeTint: 4% / 11% / 0%)

    /// Badge fill opacity applied over the semantic status color.
    static let badgeTintLight: Double = 0.04
    static let badgeTintDark: Double = 0.11
    static let badgeTintContrast: Double = 0.0

    /// Badge tint opacity for the current drawing appearance and Increase
    /// Contrast setting (light 4%, dark 11%, contrast 0%).
    static var badgeTintOpacity: Double {
        resolved(
            NSAppearance.currentDrawing(),
            light: badgeTintLight,
            dark: badgeTintDark,
            contrast: badgeTintContrast
        )
    }

    // MARK: - Private helpers

    /// Picks the token variant for an appearance, preferring the contrast
    /// column when Increase Contrast is enabled.
    private static func resolved<T>(
        _ appearance: NSAppearance,
        light: T,
        dark: T,
        contrast: T
    ) -> T {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return contrast
        }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }

    /// Builds a dynamic SwiftUI color backed by an NSColor dynamic provider
    /// so light/dark/contrast resolve per effective appearance.
    private static func dynamicColor(
        name: String,
        light: String,
        dark: String,
        contrast: String
    ) -> Color {
        let lightColor = hexColor(light)
        let darkColor = hexColor(dark)
        let contrastColor = hexColor(contrast)
        let dynamic = NSColor(name: NSColor.Name(name)) { appearance in
            resolved(appearance, light: lightColor, dark: darkColor, contrast: contrastColor)
        }
        return Color(nsColor: dynamic)
    }

    /// Parses a `#rrggbb` token value into an opaque sRGB color.
    private static func hexColor(_ hex: String) -> NSColor {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return .black
        }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
