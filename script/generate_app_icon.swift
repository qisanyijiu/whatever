#!/usr/bin/env swift
import AppKit
import Foundation

struct IconLayer {
    let name: String
    let pixels: Int
}

let layers = [
    IconLayer(name: "icon_16x16.png", pixels: 16),
    IconLayer(name: "icon_16x16@2x.png", pixels: 32),
    IconLayer(name: "icon_32x32.png", pixels: 32),
    IconLayer(name: "icon_32x32@2x.png", pixels: 64),
    IconLayer(name: "icon_128x128.png", pixels: 128),
    IconLayer(name: "icon_128x128@2x.png", pixels: 256),
    IconLayer(name: "icon_256x256.png", pixels: 256),
    IconLayer(name: "icon_256x256@2x.png", pixels: 512),
    IconLayer(name: "icon_512x512.png", pixels: 512),
    IconLayer(name: "icon_512x512@2x.png", pixels: 1024)
]

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let workDirectory = root.appendingPathComponent(".build/app-icon", isDirectory: true)
let iconset = workDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let previewURL = resources.appendingPathComponent("AppIcon.png")
let icnsURL = resources.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: workDirectory)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

for layer in layers {
    let image = renderIcon(pixels: layer.pixels)
    let url = iconset.appendingPathComponent(layer.name)
    try writePNG(image, to: url)

    if layer.pixels == 1024 {
        try writePNG(image, to: previewURL)
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(
        domain: "AppIcon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
    )
}

print("Generated \(icnsURL.path)")

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let scale = CGFloat(pixels) / 1024
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = rect.size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    rect.fill()

    drawWhiteBackground(in: rect, scale: scale)
    drawCreamBear(scale: scale)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawWhiteBackground(in rect: NSRect, scale: CGFloat) {
    let inset = 48 * scale
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let radius = 218 * scale
    let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 30 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()

    let gradient = NSGradient(colors: [
        NSColor(red: 1.0, green: 1.0, blue: 0.985, alpha: 1),
        NSColor(red: 0.985, green: 0.975, blue: 0.94, alpha: 1)
    ])!
    gradient.draw(in: backgroundPath, angle: 90)

    NSShadow().set()

    let innerPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 14 * scale, dy: 14 * scale), xRadius: 204 * scale, yRadius: 204 * scale)
    NSColor.white.withAlphaComponent(0.62).setStroke()
    innerPath.lineWidth = 5 * scale
    innerPath.stroke()
}

func drawCreamBear(scale: CGFloat) {
    let cream = NSColor(red: 0.95, green: 0.82, blue: 0.58, alpha: 1)
    let creamLight = NSColor(red: 1.0, green: 0.90, blue: 0.70, alpha: 1)
    let creamDark = NSColor(red: 0.78, green: 0.58, blue: 0.34, alpha: 1)
    let muzzle = NSColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 1)
    let blush = NSColor(red: 1.0, green: 0.63, blue: 0.62, alpha: 0.58)
    let ink = NSColor(red: 0.20, green: 0.13, blue: 0.08, alpha: 1)

    let bearShadow = NSShadow()
    bearShadow.shadowColor = NSColor(red: 0.45, green: 0.30, blue: 0.12, alpha: 0.18)
    bearShadow.shadowBlurRadius = 24 * scale
    bearShadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    bearShadow.set()

    fillOval(x: 278, y: 160, width: 468, height: 384, color: creamLight, scale: scale)
    fillOval(x: 194, y: 578, width: 246, height: 246, color: cream, scale: scale)
    fillOval(x: 584, y: 578, width: 246, height: 246, color: cream, scale: scale)
    fillOval(x: 198, y: 292, width: 628, height: 544, color: cream, scale: scale)

    NSShadow().set()

    fillOval(x: 252, y: 630, width: 128, height: 128, color: muzzle, scale: scale)
    fillOval(x: 644, y: 630, width: 128, height: 128, color: muzzle, scale: scale)
    fillOval(x: 354, y: 366, width: 316, height: 204, color: muzzle, scale: scale)
    fillOval(x: 300, y: 454, width: 84, height: 58, color: blush, scale: scale)
    fillOval(x: 640, y: 454, width: 84, height: 58, color: blush, scale: scale)

    fillOval(x: 374, y: 552, width: 52, height: 62, color: ink, scale: scale)
    fillOval(x: 598, y: 552, width: 52, height: 62, color: ink, scale: scale)
    fillOval(x: 492, y: 488, width: 40, height: 32, color: ink, scale: scale)

    strokeSmile(color: ink, scale: scale)

    fillOval(x: 344, y: 190, width: 132, height: 118, color: cream, scale: scale)
    fillOval(x: 548, y: 190, width: 132, height: 118, color: cream, scale: scale)

    strokeOval(x: 198, y: 292, width: 628, height: 544, color: creamDark.withAlphaComponent(0.26), lineWidth: 10, scale: scale)
}

func fillOval(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, scale: CGFloat) {
    let path = NSBezierPath(ovalIn: NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale))
    color.setFill()
    path.fill()
}

func strokeOval(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, lineWidth: CGFloat, scale: CGFloat) {
    let path = NSBezierPath(ovalIn: NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale))
    color.setStroke()
    path.lineWidth = lineWidth * scale
    path.stroke()
}

func strokeSmile(color: NSColor, scale: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 512 * scale, y: 486 * scale))
    path.line(to: NSPoint(x: 512 * scale, y: 460 * scale))
    path.move(to: NSPoint(x: 512 * scale, y: 460 * scale))
    path.curve(
        to: NSPoint(x: 458 * scale, y: 458 * scale),
        controlPoint1: NSPoint(x: 498 * scale, y: 438 * scale),
        controlPoint2: NSPoint(x: 474 * scale, y: 438 * scale)
    )
    path.move(to: NSPoint(x: 512 * scale, y: 460 * scale))
    path.curve(
        to: NSPoint(x: 566 * scale, y: 458 * scale),
        controlPoint1: NSPoint(x: 526 * scale, y: 438 * scale),
        controlPoint2: NSPoint(x: 550 * scale, y: 438 * scale)
    )
    color.setStroke()
    path.lineWidth = 12 * scale
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "AppIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"]
        )
    }
    try data.write(to: url, options: .atomic)
}
