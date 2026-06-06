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

    drawRoundedBackground(in: rect, scale: scale)
    drawGlyphs(in: rect, scale: scale)
    drawBlankLines(scale: scale)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawRoundedBackground(in rect: NSRect, scale: CGFloat) {
    let inset = 48 * scale
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let radius = 218 * scale
    let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.055, green: 0.067, blue: 0.09, alpha: 1),
        NSColor(red: 0.10, green: 0.13, blue: 0.17, alpha: 1)
    ])!
    gradient.draw(in: backgroundPath, angle: 130)

    NSShadow().set()

    let glossRect = NSRect(x: 160 * scale, y: 620 * scale, width: 704 * scale, height: 190 * scale)
    let glossPath = NSBezierPath(roundedRect: glossRect, xRadius: 95 * scale, yRadius: 95 * scale)
    NSColor.white.withAlphaComponent(0.045).setFill()
    glossPath.fill()
}

func drawGlyphs(in rect: NSRect, scale: CGFloat) {
    let chineseFont = NSFont.systemFont(ofSize: 212 * scale, weight: .semibold)
    let englishFont = NSFont.systemFont(ofSize: 386 * scale, weight: .semibold)

    drawText(
        "中",
        font: chineseFont,
        color: NSColor(red: 0.22, green: 0.84, blue: 0.61, alpha: 1),
        in: NSRect(x: 236 * scale, y: 462 * scale, width: 240 * scale, height: 250 * scale)
    )

    drawText(
        "A",
        font: englishFont,
        color: NSColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1),
        in: NSRect(x: 418 * scale, y: 328 * scale, width: 330 * scale, height: 440 * scale)
    )
}

func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle
    ]
    text.draw(in: rect, withAttributes: attributes)
}

func drawBlankLines(scale: CGFloat) {
    let lines: [(CGFloat, CGFloat, NSColor)] = [
        (276, 268, NSColor(red: 0.22, green: 0.84, blue: 0.61, alpha: 1)),
        (430, 268, NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1)),
        (584, 268, NSColor(red: 0.73, green: 0.77, blue: 0.83, alpha: 1))
    ]

    for line in lines {
        let rect = NSRect(x: line.0 * scale, y: line.1 * scale, width: 118 * scale, height: 18 * scale)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9 * scale, yRadius: 9 * scale)
        line.2.setFill()
        path.fill()
    }
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
