#!/usr/bin/env swift
//
//  dmg-background.swift
//  Renders the 600×400 installer background: warm light gradient, bronze gate
//  line, drag arrow. It is embedded into the app's Resources inside the DMG so
//  the installer needs no .background dot-folder. The light surface keeps
//  Finder's dark icon labels readable in both system appearances.
//
//  Usage: swift scripts/dmg-background.swift /path/out.png
//

import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first ?? "background.png"
let width = 600
let height = 400

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("background: no context\n".utf8))
    exit(1)
}

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xE8E0D0).cgColor, color(0xF8F7F3).cgColor] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: CGFloat(height)),
    options: []
)

// Gate line with the 24-stroke motif.
let lineY: CGFloat = 340
context.setStrokeColor(color(0xB5763A, 0.65).cgColor)
context.setLineWidth(1)
context.move(to: CGPoint(x: 56, y: lineY))
context.addLine(to: CGPoint(x: 544, y: lineY))
context.strokePath()

context.setStrokeColor(color(0xB5763A, 0.35).cgColor)
for index in 0..<24 {
    let x = 68 + CGFloat(index) * 20
    context.move(to: CGPoint(x: x, y: lineY - 4))
    context.addLine(to: CGPoint(x: x, y: lineY + 4))
}
context.strokePath()

// Drag arrow between the icon drop positions.
context.setStrokeColor(color(0xB5763A).cgColor)
context.setLineWidth(2)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 246, y: 200))
context.addLine(to: CGPoint(x: 354, y: 200))
context.strokePath()

context.move(to: CGPoint(x: 339, y: 210))
context.addLine(to: CGPoint(x: 354, y: 200))
context.addLine(to: CGPoint(x: 339, y: 190))
context.strokePath()

func draw(_ text: String, font: NSFont, color: NSColor, kern: CGFloat = 0, baseline: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: kern
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: baseline)
    CTLineDraw(line, context)
}

draw("Drag to install", font: .systemFont(ofSize: 12, weight: .medium), color: color(0x2A4A55), baseline: 150)
draw("NO-HALLA", font: .systemFont(ofSize: 11, weight: .semibold), color: color(0x854D21), kern: 3, baseline: 40)
draw("Valhalla can wait.", font: .systemFont(ofSize: 11), color: color(0x2A4A55), baseline: 22)

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("background: no image\n".utf8))
    exit(1)
}
let url = URL(fileURLWithPath: output)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("background: no destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("background: write failed\n".utf8))
    exit(1)
}
